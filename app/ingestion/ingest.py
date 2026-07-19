"""
Phase 3 - Ingestion script
Reads local documents, chunks them, generates embeddings via Azure OpenAI,
and indexes them into Azure AI Search.
"""

import os
import glob
from pypdf import PdfReader
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SimpleField,
    SearchableField,
    SearchField,
    SearchFieldDataType,
    VectorSearch,
    HnswAlgorithmConfiguration,
    VectorSearchProfile,
)
from openai import OpenAI

KEY_VAULT_NAME = "llmopslearn-kv"
KEY_VAULT_URI = f"https://{KEY_VAULT_NAME}.vault.azure.net"
SEARCH_SERVICE_NAME = "llmopslearn-search"
INDEX_NAME = "documents-index"
CHUNK_SIZE = 500
SAMPLE_DOCS_DIR = "sample_docs"

credential = DefaultAzureCredential()


def get_secrets():
    kv_client = SecretClient(vault_url=KEY_VAULT_URI, credential=credential)
    return {
        "foundry_endpoint": kv_client.get_secret("foundry-endpoint").value,
        "foundry_api_key": kv_client.get_secret("foundry-api-key").value,
        "embedding_deployment": kv_client.get_secret("embedding-deployment-name").value,
    }


def chunk_text(text, chunk_size=CHUNK_SIZE):
    chunks = []
    for i in range(0, len(text), chunk_size):
        chunk = text[i:i + chunk_size].strip()
        if chunk:
            chunks.append(chunk)
    return chunks


def load_documents(directory):
    docs = []
    for filepath in glob.glob(os.path.join(directory, "*.txt")):
        with open(filepath, "r", encoding="utf-8") as f:
            text = f.read()
        docs.append({"filename": os.path.basename(filepath), "text": text})

    for filepath in glob.glob(os.path.join(directory, "*.pdf")):
        reader = PdfReader(filepath)
        text = "\n".join(page.extract_text() or "" for page in reader.pages)
        docs.append({"filename": os.path.basename(filepath), "text": text})

    return docs


def ensure_index_exists(search_index_client, embedding_dim=1536):
    try:
        search_index_client.get_index(INDEX_NAME)
        print(f"Index '{INDEX_NAME}' already exists, skipping creation.")
        return
    except Exception:
        pass

    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SearchableField(name="content", type=SearchFieldDataType.String),
        SimpleField(name="source_file", type=SearchFieldDataType.String, filterable=True),
        SearchField(
            name="content_vector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=embedding_dim,
            vector_search_profile_name="default-vector-profile",
        ),
    ]

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name="default-hnsw")],
        profiles=[
            VectorSearchProfile(
                name="default-vector-profile",
                algorithm_configuration_name="default-hnsw",
            )
        ],
    )

    index = SearchIndex(name=INDEX_NAME, fields=fields, vector_search=vector_search)
    search_index_client.create_index(index)
    print(f"Created index '{INDEX_NAME}'.")


def embed_text(openai_client, deployment_name, text):
    response = openai_client.embeddings.create(input=text, model=deployment_name)
    return response.data[0].embedding


def main():
    print("Fetching secrets from Key Vault...")
    secrets = get_secrets()

    print("Setting up Azure OpenAI client...")
    endpoint = secrets["foundry_endpoint"].rstrip("/")
    openai_client = OpenAI(
        api_key=secrets["foundry_api_key"],
        base_url=f"{endpoint}/openai/v1/",
    )

    print("Setting up AI Search clients...")
    search_endpoint = f"https://{SEARCH_SERVICE_NAME}.search.windows.net"
    search_index_client = SearchIndexClient(endpoint=search_endpoint, credential=credential)
    search_client = SearchClient(endpoint=search_endpoint, index_name=INDEX_NAME, credential=credential)

    ensure_index_exists(search_index_client)

    print(f"Loading documents from '{SAMPLE_DOCS_DIR}'...")
    documents = load_documents(SAMPLE_DOCS_DIR)
    print(f"Loaded {len(documents)} document(s).")

    upload_batch = []
    doc_id = 0
    for doc in documents:
        chunks = chunk_text(doc["text"])
        for chunk in chunks:
            print(f"Embedding chunk from {doc['filename']}...")
            vector = embed_text(openai_client, secrets["embedding_deployment"], chunk)
            upload_batch.append({
                "id": str(doc_id),
                "content": chunk,
                "source_file": doc["filename"],
                "content_vector": vector,
            })
            doc_id += 1

    if upload_batch:
        print(f"Uploading {len(upload_batch)} chunk(s) to the search index...")
        result = search_client.upload_documents(documents=upload_batch)
        succeeded = sum(1 for r in result if r.succeeded)
        print(f"Uploaded {succeeded}/{len(upload_batch)} chunks successfully.")
    else:
        print("No chunks to upload.")


if __name__ == "__main__":
    main()