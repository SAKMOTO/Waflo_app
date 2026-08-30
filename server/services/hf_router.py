import base64
import io
from huggingface_hub import InferenceClient
from config import Settings

settings = Settings()

class HFRouter:
    def __init__(self):
        self.client = InferenceClient(api_key=settings.HF_TOKEN)
        # Standard model for text-to-image
        self.t2i_model = "black-forest-labs/FLUX.1-dev" 

    def is_image_request(self, query: str) -> bool:
        """Determines if the user query is asking to generate an image."""
        q = query.lower()
        keywords = ["generate an image", "create an image", "draw", "make an image", "generate a picture", "create a picture"]
        return any(kw in q for kw in keywords)

    def generate_image(self, prompt: str) -> str:
        """Generates an image from text and returns it as a base64 string."""
        try:
            image = self.client.text_to_image(prompt, model=self.t2i_model)
            buffered = io.BytesIO()
            image.save(buffered, format="PNG")
            img_str = base64.b64encode(buffered.getvalue()).decode("utf-8")
            return img_str
        except Exception as e:
            print(f"Hugging Face Text-to-Image Error: {e}")
            return None
