import os
from fastapi import FastAPI
from pydantic import BaseModel
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery
from openai import OpenAI
import logging
from azure.monitor.opentelemetry import configure_azure_monitor
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor

KEY_VAULT_NAME = "llmopslearn-kv"
KEY_VAULT_URI = f"https://{KEY_VAULT_NAME}.vault.azure.net"
SEARCH_SERVICE_NAME = "llmopslearn-search"
INDEX_NAME = "documents-index"
TOP_K = 3

credential = DefaultAzureCredential()
app = FastAPI(title="LLMOps RAG Orchestrator")

logger = logging.getLogger(__name__)

@app.on_event("startup")
def setup_observability():
    kv_client = SecretClient(vault_url=KEY_VAULT_URI, credential=credential)
    connection_string = kv_client.get_secret("appinsights-connection-string").value
    configure_azure_monitor(connection_string=connection_string)
    logging.getLogger().setLevel(logging.INFO)
    FastAPIInstrumentor.instrument_app(app)
    logger.info("Application Insights configured successfully.")

_secrets = None
_openai_client = None
_search_client = None


def get_secrets():
    global _secrets
    if _secrets is None:
        kv_client = SecretClient(vault_url=KEY_VAULT_URI, credential=credential)
        _secrets = {
            "embedding_deployment": kv_client.get_secret("embedding-deployment-name").value,
            "chat_deployment": kv_client.get_secret("chat-deployment-name").value,
            "litellm_master_key": kv_client.get_secret("litellm-master-key").value,
        }
    return _secrets


def get_clients():
    global _openai_client, _search_client
    secrets = get_secrets()
    if _openai_client is None:
        litellm_url = os.environ.get("LITELLM_INTERNAL_URL")
        _openai_client = OpenAI(api_key=secrets["litellm_master_key"], base_url=f"https://{litellm_url}/v1")
    if _search_client is None:
        search_endpoint = f"https://{SEARCH_SERVICE_NAME}.search.windows.net"
        _search_client = SearchClient(endpoint=search_endpoint, index_name=INDEX_NAME, credential=credential)
    return _openai_client, _search_client


def embed_text(openai_client, deployment_name, text):
    response = openai_client.embeddings.create(input=text, model=deployment_name)
    return response.data[0].embedding


def retrieve_chunks(search_client, openai_client, embedding_deployment, question):
    query_vector = embed_text(openai_client, embedding_deployment, question)
    vector_query = VectorizedQuery(vector=query_vector, k_nearest_neighbors=TOP_K, fields="content_vector")
    results = search_client.search(search_text=None, vector_queries=[vector_query], select=["content", "source_file"])
    return [{"content": r["content"], "source": r["source_file"]} for r in results]


def build_prompt(question, chunks):
    context = "\n\n".join(f"[Source: {c['source']}]\n{c['content']}" for c in chunks)
    return f"""Answer the question using ONLY the context below. If the context doesn't contain the answer, say you don't have enough information.

Context:
{context}

Question: {question}

Answer:"""


class QuestionRequest(BaseModel):
    question: str


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/ask")
def ask(req: QuestionRequest):
    logger.info(f"Received question: {req.question[:100]}")
    secrets = get_secrets()
    openai_client, search_client = get_clients()

    chunks = retrieve_chunks(search_client, openai_client, secrets["embedding_deployment"], req.question)
    logger.info(f"Retrieved {len(chunks)} chunks")
    if not chunks:
        return {"answer": "No relevant context found in the index.", "sources": []}

    prompt = build_prompt(req.question, chunks)
    response = openai_client.chat.completions.create(
        model=secrets["chat_deployment"],
        messages=[
            {"role": "system", "content": "You are a helpful assistant that answers questions strictly from the provided context."},
            {"role": "user", "content": prompt},
        ],
    )
    answer = response.choices[0].message.content
    sources = list(set(c["source"] for c in chunks))
    logger.info(f"Answer generated, sources: {sources}")
    return {"answer": answer, "sources": sources}
# retry CI/CD
# CI/CD trigger test Sat Jul 18 09:29:03 +03 2026
