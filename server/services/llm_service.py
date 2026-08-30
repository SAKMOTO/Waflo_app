import base64
import mimetypes
from huggingface_hub import InferenceClient
from config import Settings

settings = Settings()

class LLMService:
    def __init__(self):
        self.client = InferenceClient(api_key=settings.HF_TOKEN)
        # Using Qwen2.5-72B-Instruct which works successfully with your free tier token
        self.model_name = "Qwen/Qwen2.5-72B-Instruct"
        
    def generate_response(self, query: str, search_results: list[dict], file_name: str = None, file_base64: str = None):
        context_text ="\n\n".join(
            [
            f"""Source {i+1} ({result.get('url','')}):
            Content: {result.get('content','')}"""
            for i,result in enumerate(search_results)
        ]
        )

        full_prompt = f"""
       You are an advanced AI assistant.
       Use ONLY the information provided in the context or the attached file if provided.

       Context:
        {context_text}

        Query : {query}
        Please provide a comprehensive,detailed ,well-cited accurate and informative response based on the above context and the attached file. Think and reason deeply before answering. Ensure it answers the query the user is asking . Do not use your knowledge if the context does not contain relevant information, please respond with 'I don't know' or 'The provided context does not contain relevant information to answer the query.' Do not make up information or provide inaccurate details. Ensure that your response is based solely on the provided context.
        """
        
        # Build the message content
        content = []
        if file_base64 and file_name:
            mime_type, _ = mimetypes.guess_type(file_name)
            if not mime_type:
                mime_type = "application/octet-stream"
            # If the user uploaded an image and we want to use a vision model, we'd pass it here.
            # For this text model, we will just pass a note that a file was attached.
            content.append({"type": "text", "text": f"[User attached file: {file_name} of type {mime_type}]"})
        
        content.append({"type": "text", "text": full_prompt})
        
        messages = [
            {"role": "user", "content": content}
        ]

        try:
            response_stream = self.client.chat_completion(
                model=self.model_name,
                messages=messages,
                max_tokens=1024,
                stream=True
            )
            for chunk in response_stream:
                if chunk.choices[0].delta.content:
                    yield chunk.choices[0].delta.content
        except Exception as e:
            print(f"Hugging Face Error: {e}")
            yield f"\n\n[Hugging Face Error: {str(e)}. Please check your HF_TOKEN.]"
