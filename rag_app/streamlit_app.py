"""Chat UI for the humanoid robotics RAG.

It only talks to the API over HTTP (it does not import rag.py), so start the API first:
    Terminal 1:  uv run uvicorn rag_app.api:app --reload
    Terminal 2:  uv run streamlit run rag_app/streamlit_app.py

Each question is answered independently (no memory of earlier questions);
the sidebar filters apply to every new question.
"""

from __future__ import annotations

import os

import requests
import streamlit as st

API_URL = os.getenv("RAG_API_URL", "http://localhost:8000")
REQUEST_TIMEOUT_S = 180     # first call can be slow while Databricks resources wake up

COMPANY_TYPE_LABELS = {
    "humanoid_maker": "Humanoid robot maker",
    "tier1": "Automotive tier-1 supplier",
    "investor": "Investor",
    "customer": "Customer",
    "technology_partner": "Technology partner",
    "other": "Other",
}

st.set_page_config(page_title="Humanoid Robotics RAG", page_icon="🤖", layout="wide")


# ---------------------------------------------------------------------------
# API calls
# ---------------------------------------------------------------------------
class ApiError(Exception):
    pass


def _api_error(response: requests.Response) -> ApiError:
    """Turn an error response into a readable message."""
    try:
        detail = response.json().get("detail")
    except ValueError:
        detail = response.text
    if isinstance(detail, list):        # 422: list of validation errors
        detail = "; ".join(f"{'.'.join(map(str, d.get('loc', [])[1:]))}: {d.get('msg')}"
                           for d in detail)
    return ApiError(f"API error {response.status_code}: {detail}")


def api_get(path: str) -> dict:
    try:
        response = requests.get(f"{API_URL}{path}", timeout=REQUEST_TIMEOUT_S)
    except requests.ConnectionError as exc:
        raise ApiError(f"Cannot reach the API at {API_URL}.") from exc
    if not response.ok:
        raise _api_error(response)
    return response.json()


def api_ask(payload: dict) -> dict:
    try:
        response = requests.post(f"{API_URL}/ask", json=payload, timeout=REQUEST_TIMEOUT_S)
    except requests.ConnectionError as exc:
        raise ApiError(f"Cannot reach the API at {API_URL}.") from exc
    except requests.Timeout as exc:
        raise ApiError("The API took too long to answer. Try again in a moment.") from exc
    if not response.ok:
        raise _api_error(response)
    return response.json()


@st.cache_data(show_spinner="Loading filter options...")
def load_filter_options() -> dict:
    # Cached in Streamlit too, so the sidebar does not call the API on every rerun.
    # Errors are not cached: a failed load is retried on the next rerun.
    return api_get("/filters")


# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------
def md(text: str) -> str:
    """Escape '$' so amounts like $1B are not rendered as math."""
    return text.replace("$", r"\$")


def render_answer(message: dict) -> None:
    if message.get("error"):
        st.error(message["error"])
        return

    st.markdown(md(message["answer"]))
    if message.get("filters"):
        st.caption("Filters: " + " · ".join(message["filters"]))

    if message["sources"]:
        st.markdown("**Sources**")
        for s in message["sources"]:
            note = " · *translated from Chinese*" if s["translated_from_chinese"] else ""
            st.markdown(f"[{s['number']}] [{md(s['title'])}]({s['url']}) "
                        f"— {md(s['publisher'])}, {s['publish_date']}{note}")

    chunks = message["chunks"]
    with st.expander(f"Retrieved chunks ({len(chunks)})"):
        for c in chunks:
            st.markdown(f"**{c['chunk_id']}** · score {c['score']:.3f} · {c['publish_date']}  \n"
                        f"{md(c['title'])}  \n"
                        f"*Companies: {md(c['companies_info'] or '—')}*")
            st.text(c["chunk_text"])
            st.divider()


# ---------------------------------------------------------------------------
# Page
# ---------------------------------------------------------------------------
st.title("🤖 Humanoid Robotics Market Intelligence")
st.caption("Ask about partnerships, funding and deployments in the humanoid robotics industry. "
           "Answers use only the indexed documents and cite their sources.")

# Is the API running?
try:
    api_get("/health")
except ApiError as exc:
    st.error(f"{exc}\n\nStart it in another terminal:\n\n"
             "`uv run uvicorn rag_app.api:app --reload`")
    st.stop()

# Filter options (fall back to empty lists if the warehouse query fails)
try:
    options = load_filter_options()
except ApiError as exc:
    options = {"companies": [], "company_types": list(COMPANY_TYPE_LABELS),
               "source_types": [], "years": []}
    st.sidebar.warning(f"Could not load filter options; some filters are unavailable.\n\n{exc}")

companies = {c["company_id"]: c for c in options["companies"]}

# ---- Sidebar: filters ------------------------------------------------------
with st.sidebar:
    st.header("Filters")
    st.caption("Applied to each new question.")

    company_id = st.selectbox(
        "Company",
        options=[None, *companies],
        format_func=lambda cid: "All companies" if cid is None else
            f"{companies[cid]['company_name']} ({companies[cid]['company_type'] or '—'})",
    )
    company_type = st.selectbox(
        "Company type",
        options=[None, *options["company_types"]],
        format_func=lambda t: "All types" if t is None else COMPANY_TYPE_LABELS.get(t, t),
        help="Only documents that involve at least one company of this type.",
    )
    year_from = st.selectbox(
        "Published from",
        options=[None, *options["years"]],
        format_func=lambda y: "Any year" if y is None else f"{y} onwards",
    )
    source_types = st.multiselect(
        "Source type", options=options["source_types"],
        placeholder="All source types",
    )
    top_k = st.slider("Chunks to retrieve (top k)", min_value=1, max_value=20, value=5,
                      help="More chunks = better coverage for broad questions, longer prompts.")

    st.divider()
    if st.button("Clear conversation", use_container_width=True):
        st.session_state.messages = []
        st.rerun()


# ---- Conversation ----------------------------------------------------------
if "messages" not in st.session_state:
    st.session_state.messages = []

for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        if message["role"] == "user":
            st.markdown(md(message["content"]))
        else:
            render_answer(message)

question = st.chat_input("e.g. Which tier-1 suppliers partnered with humanoid makers?")
if question:
    st.session_state.messages.append({"role": "user", "content": question})
    with st.chat_message("user"):
        st.markdown(md(question))

    payload = {"question": question, "top_k": top_k, "company_id": company_id,
               "company_type": company_type, "year_from": year_from,
               "source_types": source_types or None}

    # Human-readable list of the filters used, shown under the answer
    used = []
    if company_id:
        used.append(f"company = {companies[company_id]['company_name']}")
    if company_type:
        used.append(f"type = {COMPANY_TYPE_LABELS.get(company_type, company_type)}")
    if year_from:
        used.append(f"from {year_from}")
    if source_types:
        used.append("source = " + ", ".join(source_types))
    used.append(f"top k = {top_k}")

    with st.chat_message("assistant"):
        with st.spinner("Searching documents and writing the answer..."):
            try:
                result = api_ask(payload)
                message = {"role": "assistant", "answer": result["answer"],
                           "sources": result["sources"], "chunks": result["chunks"],
                           "filters": used}
            except ApiError as exc:
                message = {"role": "assistant", "error": str(exc)}
        render_answer(message)
    st.session_state.messages.append(message)
