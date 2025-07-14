from transformers import AutoTokenizer, AutoModelForCausalLM, set_seed
import torch
import openai
import replicate, os
import json
import requests
import time
from sentence_transformers import SentenceTransformer
from sklearn.metrics.pairwise import cosine_similarity
from sentence_transformers import SentenceTransformer, util
from PyPDF2 import PdfReader
import ollama

import numpy as np
from groq import Groq

# client = Groq(
#     api_key= "",
#     # "",
# )

HF_MODEL_URLS = {
    "mistral-7b": "mistralai/Mistral-7B-Instruct-v0.1",
    "llama-7b": "meta-llama/Llama-2-7b-chat-hf",
}

OPENAI_MODELS = {
    "gpt3.5": "gpt-3.5-turbo",
    "gpt4": "gpt-4",
}

def load_document(doc_path):
    reader = PdfReader(doc_path)
    text = ""
    for page in reader.pages:
        page_text = page.extract_text()
        if page_text:
            text += page_text
    return text

def chunk_text(text, chunk_size=500, overlap=100):
    words = text.split()
    chunks = []
    for i in range(0, len(words), chunk_size - overlap):
        chunks.append(" ".join(words[i:i + chunk_size]))
    return chunks

def get_openai_embeddings(texts, model="text-embedding-3-small"):
    from openai import OpenAI
    client = OpenAI(api_key="")  # your OpenAI key
    response = client.embeddings.create(
        input=texts,
        model=model,
        encoding_format="float"
    )
    # Sort by index to preserve input order
    embeddings = [e.embedding for e in sorted(response.data, key=lambda x: x.index)]
    return embeddings

def retrieve_relevant_chunks(chunks, query, model_name="text-embedding-3-small", top_k=3):
    chunk_embeddings = get_openai_embeddings(chunks, model=model_name)
    query_embedding = get_openai_embeddings([query], model=model_name)[0]
    similarities = cosine_similarity([query_embedding], chunk_embeddings)[0]
    top_indices = np.argsort(similarities)[-top_k:][::-1]
    return [chunks[i] for i in top_indices]

def get_rag(document, prompts, embedding_model="text-embedding-3-small"):
    doc_text = load_document(document)
    chunks = chunk_text(doc_text)
    combined_prompt = " ".join(prompts)
    relevant_chunks = retrieve_relevant_chunks(chunks, combined_prompt, model_name=embedding_model)
    relevant_text = "\n".join(relevant_chunks)
    prompts = [f"{relevant_text}\n{p}" for p in prompts]
    return prompts

def prompt_gpt(prompts, use_rag=False, model_name="alias-code", document_chunks=None, query=None):
    """
    Generate responses using GPT, Gemini, Ollama, or other models, with optional RAG functionality.

    Args:
        prompts (list): List of input prompts.
        use_rag (bool): Whether to use Retrieval-Augmented Generation (RAG).
        model_name (str): The name of the model to use.
        document_chunks (list): List of document chunks for RAG (optional).
        query (str): Query for retrieving relevant chunks (optional).

    Returns:
        dict: Dictionary containing prompts and their corresponding answers.
    """
    import requests
    import json

    ans_dict = {}

    if "alias" in model_name:
        # Use alias-code API
        url = ''
        headers = {
            'accept': 'application/json',
            'Authorization': '',
            'Content-Type': 'application/json',
        }
        for i, input_prompt in enumerate(prompts):
            data = {
                "model": model_name,
                "messages": [{"role": "system", "content": "Strictly follow the format to return the answer"},
                             {"role": "user", "content": input_prompt}],
                "temperature": 0,
                "top_p": 1,
                "top_k": -1,
                "n": 1,
                "max_tokens": 4096,
                "stop": ["string"],
                "stream": False,
                "user": "string"
            }
            response = requests.post(url, headers=headers, data=json.dumps(data))
            if response.status_code == 200:
                answer = response.json()['choices'][0]['message']['content']
            else:
                answer = f"Error: {response.status_code} - {response.text}"
            ans_dict[f"prompt_{i}"] = input_prompt
            ans_dict[f"answer_{i}"] = answer

    elif "gemini" in model_name:
        from google import genai
        from google.genai import types

        # Use Gemini API
        # API_KEY = userdata.get('')
        client = genai.Client(api_key='')

        for i, input_prompt in enumerate(prompts):
            try:
                response = client.models.generate_content(
                    model=model_name,
                    contents=input_prompt,
                    
                    config=types.GenerateContentConfig(
                        tools=[types.Tool(code_execution=types.ToolCodeExecution)],
                        temperature=0,
                        topP=1
                    )
                )

                output_parts = []
                for part in response.candidates[0].content.parts:
                    if part.text:
                        output_parts.append(part.text)
                    elif part.executable_code:
                        output_parts.append(part.executable_code.code)
                    elif part.code_execution_result:
                        output_parts.append(part.code_execution_result.output)

                answer = "\n".join(output_parts)

            except Exception as e:
                answer = f"Gemini API Error: {str(e)}"

            ans_dict[f"prompt_{i}"] = input_prompt
            ans_dict[f"answer_{i}"] = answer
    
    elif "deepcoder" in model_name or "agentica" in model_name:
        from openai import OpenAI
        print("here")
        client = OpenAI(
            base_url="https://openrouter.ai/api/v1",
            api_key="",  # Replace with your actual key
        )

        for i, input_prompt in enumerate(prompts):
            try:
                completion = client.chat.completions.create(
                    model="agentica-org/deepcoder-14b-preview:free",  # optional namespace cleanup
                    messages=[{"role": "user", "content": input_prompt}],
                    
                )
                print("hi")
                answer = completion.choices[0].message.content
            except Exception as e:
                answer = f"OpenRouter Error: {str(e)}"

            ans_dict[f"prompt_{i}"] = input_prompt
            ans_dict[f"answer_{i}"] = answer


    elif "gpt" in model_name or "o3" in model_name:
        import openai
        for i, input_prompt in enumerate(prompts):
            try:
                response = openai.ChatCompletion.create(
                    model=model_name,
                    messages=[
                        {"role": "system", "content": "Strictly follow the format to return the answer"},
                        {"role": "user", "content": input_prompt}
                    ],
                    # temperature=0,
                )
                answer = response['choices'][0]['message']['content']
            except openai.error.OpenAIError as e:
                answer = f"OpenAI Error: {str(e)}"

            ans_dict[f"prompt_{i}"] = input_prompt
            ans_dict[f"answer_{i}"] = answer

    elif "claude" in model_name:
        import anthropic
        # Use Claude (Anthropic) API
        client = anthropic.Anthropic(api_key="")

        for i, input_prompt in enumerate(prompts):
            try:
                message = client.messages.create(
                    model=model_name,
                    messages=[
                        {"role": "user", "content": input_prompt}
                    ],
                    max_tokens = 8000
                )
                answer = "".join([block.text for block in message.content])

            except Exception as e:
                answer = f"Claude API Error: {str(e)}"

            ans_dict[f"prompt_{i}"] = input_prompt
            ans_dict[f"answer_{i}"] = answer

    elif "qwen" in model_name or "code" in model_name or "deepseek" in model_name:
        import ollama
        for i, input_prompt in enumerate(prompts):
            try:
                response = ollama.generate(model=model_name, prompt=input_prompt, options = {'temperature': 0, 'top_p':1})
                answer = response.response.strip()
            except Exception as e:
                answer = f"Ollama Error: {str(e)}"

            ans_dict[f"prompt_{i}"] = input_prompt
            ans_dict[f"answer_{i}"] = answer
    

    else:
        raise ValueError(f"Unsupported model name: {model_name}")
    # else:
    #     # Use generic fallback
    #     for i, input_prompt in enumerate(prompts):
    #         try:
    #             chat_completion = client.chat.completions.create(
    #                 messages=[
    #                     {"role": "system", "content": "Strictly follow the format to return the answer"},
    #                     {"role": "user", "content": input_prompt}
    #                 ],
    #                 temperature=0,
    #                 model=model_name,
    #             )
    #             answer = chat_completion.choices[0].message.content
    #         except Exception as e:
    #             answer = f"Error: {str(e)}"

    #         ans_dict[f"prompt_{i}"] = input_prompt
    #         ans_dict[f"answer_{i}"] = answer

    return ans_dict


def prompt_gpt_iter(prompts, use_rag=False, model_name="alias-code", document_chunks=None, query=None):
    import requests
    import json

    print(f"Using model in ITER: {model_name}")
    ans_dict = {}

    if "abd" in model_name:
        # Use alias-code API
        url = ''
        headers = {
            'accept': 'application/json',
            'Authorization': '',
            'Content-Type': 'application/json',
        }
        for i, input_prompt in enumerate(prompts):
            conversation = input_prompt

            data = {
                "model": model_name,
                "messages": conversation,
                "temperature": 0,
                "top_p": 1,
                "top_k": -1,
                "n": 1,
                "max_tokens": 4096,
                "stop": ["string"],
                "stream": False,
                "user": "string"
            }

            response = requests.post(url, headers=headers, data=json.dumps(data))
            response_dict = response.json()

            if response.status_code == 200:
                answer = response_dict['choices'][0]['message']['content']
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = answer
            else:
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = f"Error: {response.status_code} - {response.text}"

    elif "gpt" in model_name:
        # Use OpenAI GPT-based models
        for i, input_prompt in enumerate(prompts):
            conversation = input_prompt

            try:
                response = openai.ChatCompletion.create(
                    model=model_name,
                    messages=conversation,
                    temperature=0,
                    max_tokens=4096,
                )
                answer = response['choices'][0]['message']['content']
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = answer

            except openai.error.OpenAIError as e:
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = f"Error: {str(e)}"

    elif "qwen-2.5-coder-32b" in model_name:
        # Use Ollama inference
        for i, input_prompt in enumerate(prompts):
            try:
                response = ollama.chat(model="qwen2.5-coder:32b", messages=input_prompt)
                answer = response["message"]["content"]
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = answer
            except Exception as e:
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = f"Error: {str(e)}"
    elif "alias-code" in model_name:
        # Use Ollama inference
        for i, input_prompt in enumerate(prompts):
            try:
                response = ollama.chat(model="qwen2.5-coder:14b", messages=input_prompt)
                answer = response["message"]["content"]
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = answer
            except Exception as e:
                ans_dict[f"prompt_{i}"] = input_prompt
                ans_dict[f"answer_{i}"] = f"Error: {str(e)}"

    else:
        # Use Groq API or other fallback
        for i, input_prompt in enumerate(prompts):
            conversation = [{"role": "system", "content": "Strictly follow the format to return the answer"}]
            conversation.append({"role": "user", "content": input_prompt})

            chat_completion = client.chat.completions.create(
                messages=conversation,
                temperature=0,
                model=model_name,
            )
            answer = chat_completion.choices[0].message.content

            ans_dict[f"prompt_{i}"] = input_prompt
            ans_dict[f"answer_{i}"] = answer

    return ans_dict

