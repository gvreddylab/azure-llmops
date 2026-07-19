from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
from azure.search.documents import SearchClient
from azure.search.documents.models import VectorizedQuery
from openai import OpenAI

KEY_VAULT_NAME = "llmopslearn-kv"
KEY_VAULT_URI = f"https://{KEY_VAULT_NAME}.vault.azure.net"
SEARCH_SERVICE_NAME = "llmopslearn-search"
INDEX_NAME = "documents-index"
TOP_K = 3

credential = DefaultAzureCredential()


def get_secrets():
    kv_client = SecretClient(vault_url=KEY_VAULT_URI, credential=credential)
    return {
        "foundry_endpoint": kv_client.get_secret("foundry-endpoint").value,
        "foundry_api_key": kv_client.get_secret("foundry-api-key").value,
        "embedding_deployment": kv_client.get_secret("embedding-deployment-name").value,
        "chat_deployment": kv_client.get_secret("chat-deployment-name").value,
    }


def embed_text(openai_client, deployment_name, text):
    response = openai_client.embeddings.create(input=text, model=deployment_name)
    return response.data[0].embedding


def retrieve_chunks(search_client, openai_client, embedding_deployment, question):
    query_vector = embed_text(openai_client, embedding_deployment, question)
    vector_query = VectorizedQuery(
        vector=query_vector,
        k_nearest_neighbors=TOP_K,
        fields="content_vector",
    )
    results = search_client.search(
        search_text=None,
        vector_queries=[vector_query],
        select=["content", "source_file"],
    )
    return [{"content": r["content"], "source": r["source_file"]} for r in results]


def build_prompt(question, chunks):
    context = "\n\n".join(f"[Source: {c['source']}]\n{c['content']}" for c in chunks)
    return f"""Answer the question using ONLY the context below. If the context doesn't contain the answer, say you don't have enough information.

Context:
{context}

Question: {question}

Answer:"""


def ask(openai_client, chat_deployment, question, chunks):
    prompt = build_prompt(question, chunks)
    response = openai_client.chat.completions.create(
        model=chat_deployment,
        messages=[
            {"role": "system", "content": "You are a helpful assistant that answers questions strictly from the provided context."},
            {"role": "user", "content": prompt},
        ],
    )
    return response.choices[0].message.content


def main():
    print("Fetching secrets from Key Vault...")
    secrets = get_secrets()

    endpoint = secrets["foundry_endpoint"].rstrip("/")
    openai_client = OpenAI(
        api_key=secrets["foundry_api_key"],
        base_url=f"{endpoint}/openai/v1/",
    )

    search_endpoint = f"https://{SEARCH_SERVICE_NAME}.search.windows.net"
    search_client = SearchClient(endpoint=search_endpoint, index_name=INDEX_NAME, credential=credential)

    print("\nRAG orchestrator ready. Type a question (or 'quit' to exit).\n")

    while True:
        question = input("Question: ").strip()
        if question.lower() in ("quit", "exit"):
            break
        if not question:
            continue

        chunks = retrieve_chunks(search_client, openai_client, secrets["embedding_deployment"], question)

        if not chunks:
            print("Answer: No relevant context found in the index.\n")
            continue

        print(f"(Retrieved {len(chunks)} chunk(s) from: {', '.join(set(c['source'] for c in chunks))})")

        answer = ask(openai_client, secrets["chat_deployment"], question, chunks)
        print(f"\nAnswer: {answer}\n")


if __name__ == "__main__":
    main()
