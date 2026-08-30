# 🦙 **Ollama Setup Guide - Self-Hosted AI Model**

## 📌 **What is Ollama?**

Ollama lets you run **large language models locally** without API limits or costs. 

### **Why Use Ollama?**
- ✅ **Unlimited requests** - No rate limits
- ✅ **Free** - No API costs
- ✅ **Private** - Data never leaves your server
- ✅ **Offline capable** - Works without internet
- ⚠️ Trade-off: Slightly slower than cloud APIs

---

## 🚀 **Installation (5-10 minutes)**

### **Option 1: Local Machine (macOS/Linux/Windows)**

1. **Download Ollama**
   - Go to https://ollama.ai
   - Click "Download"
   - Install for your OS

2. **Start Ollama**
   ```bash
   # macOS/Linux: Will run in background
   ollama serve
   
   # Windows: Open Ollama application
   ```

3. **Pull a Model** (in another terminal)
   ```bash
   # Lightweight & fast (4GB) - RECOMMENDED for beginners
   ollama pull mistral
   
   # OR other options:
   ollama pull neural-chat      # Good for chat, 4GB
   ollama pull dolphin-mixtral  # Powerful, 26GB
   ollama pull llama2           # Meta's Llama2, 7GB
   ollama pull orca-mini        # Tiny, 2GB (basic only)
   ```

4. **Test It**
   ```bash
   curl http://localhost:11434/api/generate -d '{
     "model": "mistral",
     "prompt": "What is artificial intelligence?"
   }'
   ```

### **Option 2: VPS/Cloud Server ($5-10/month)**

If you want to share Ollama between multiple users:

1. **Rent a VPS**
   - Options: DigitalOcean, Linode, Vultr, AWS EC2
   - Specs: 4GB RAM, 20GB disk minimum
   - Cost: ~$5-10/month

2. **Install Ollama**
   ```bash
   # SSH into your server
   ssh root@your_server_ip
   
   # Install
   curl https://ollama.ai/install.sh | sh
   
   # Pull model
   ollama pull mistral
   
   # Start as background service
   nohup ollama serve > ollama.log 2>&1 &
   ```

3. **Allow Remote Access**
   ```bash
   # Edit Ollama config to allow connections from your app
   # Set environment variable:
   export OLLAMA_HOST=0.0.0.0:11434
   
   # Then restart: ollama serve
   ```

---

## 🔧 **Integration with Waflo**

### **Step 1: Update Backend Dependencies**

```bash
cd server
pip install requests
# Already have everything else!
```

### **Step 2: Replace llm_service.py**

Replace the entire `server/services/llm_service.py` with:

```python
import requests
import json
from typing import Generator

class LLMService:
    """Use Ollama instead of Hugging Face"""
    
    def __init__(self):
        # Change this URL to your Ollama server
        # Local: http://localhost:11434
        # Remote: http://your-vps-ip:11434
        self.ollama_url = "http://localhost:11434/api/generate"
        self.model = "mistral"  # Change if using different model
    
    def generate_response(
        self,
        query: str,
        search_results: list[dict],
        file_name: str = None,
        file_base64: str = None
    ) -> Generator[str, None, None]:
        """
        Generate response using Ollama
        
        Yields:
            Chunks of response text (streaming)
        """
        
        # Build context from search results
        context_text = "\n\n".join([
            f"Source {i+1} ({result.get('url', 'Unknown')})\n"
            f"Title: {result.get('title', 'No title')}\n"
            f"Content: {result.get('content', 'No content')}"
            for i, result in enumerate(search_results)
        ])
        
        # Build the prompt
        prompt = f"""You are a helpful AI assistant. Answer the user's question based ONLY on the provided sources.

IMPORTANT RULES:
1. Use ONLY information from the sources below
2. If the answer is not in the sources, say "The provided sources don't contain this information"
3. Don't make up information or use general knowledge
4. Cite the source number when referencing information
5. Be clear, concise, and well-structured

SOURCES:
{context_text}

USER QUESTION: {query}

ANSWER:"""
        
        try:
            # Call Ollama API
            response = requests.post(
                self.ollama_url,
                json={
                    "model": self.model,
                    "prompt": prompt,
                    "stream": True,
                    "temperature": 0.7,  # Balance between creativity & accuracy
                },
                timeout=300  # 5 minute timeout
            )
            
            response.raise_for_status()  # Raise if status != 200
            
            # Stream response
            for line in response.iter_lines():
                if line:
                    try:
                        chunk = json.loads(line)
                        if chunk.get("response"):
                            yield chunk["response"]
                    except json.JSONDecodeError:
                        continue
        
        except requests.ConnectionError:
            yield "\n\n❌ **Error**: Cannot connect to Ollama at " + self.ollama_url
            yield "\n\nMake sure Ollama is running: `ollama serve`"
        
        except Exception as e:
            yield f"\n\n❌ **Error**: {str(e)}"
```

### **Step 3: Update config.py (Optional)**

If you want to use environment variables:

```python
# Add to server/config.py
class Settings(BaseSettings):
    # ... existing settings ...
    
    # Ollama configuration
    OLLAMA_BASE_URL: str = "http://localhost:11434"
    OLLAMA_MODEL: str = "mistral"
```

Then update llm_service.py:
```python
from config import settings

class LLMService:
    def __init__(self):
        self.ollama_url = f"{settings.OLLAMA_BASE_URL}/api/generate"
        self.model = settings.OLLAMA_MODEL
```

### **Step 4: Test Ollama**

```bash
# Terminal 1: Start Ollama
ollama serve

# Terminal 2: Start Python backend
cd server
python main.py

# Terminal 3: Test with curl
curl -X POST http://localhost:8000/chat \
  -H "Content-Type: application/json" \
  -d '{"query": "What is Python?"}'
```

---

## 🎯 **Model Comparison**

| Model | Size | Speed | Quality | Use Case |
|-------|------|-------|---------|----------|
| **orca-mini** | 2GB | ⚡⚡⚡⚡⚡ | ⭐ | Quick tests, small server |
| **mistral** | 4GB | ⚡⚡⚡⚡ | ⭐⭐⭐⭐ | **Best for Waflo** |
| **neural-chat** | 4GB | ⚡⚡⚡⚡ | ⭐⭐⭐⭐ | Conversational, similar to mistral |
| **llama2** | 7GB | ⚡⚡⚡ | ⭐⭐⭐⭐⭐ | High quality, slightly slower |
| **dolphin-mixtral** | 26GB | ⚡⚡ | ⭐⭐⭐⭐⭐ | Best quality, needs beefy server |

**Recommendation**: Start with `mistral` (good balance of speed/quality)

---

## ⚙️ **Production Deployment**

### **Deploy Ollama to VPS**

```bash
# 1. SSH into server
ssh root@your_vps_ip

# 2. Install Ollama
curl https://ollama.ai/install.sh | sh

# 3. Pull model
ollama pull mistral

# 4. Create systemd service (auto-start)
sudo tee /etc/systemd/system/ollama.service > /dev/null <<EOF
[Unit]
Description=Ollama
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/ollama serve
Environment="OLLAMA_HOST=0.0.0.0:11434"
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 5. Enable service
sudo systemctl enable ollama
sudo systemctl start ollama
sudo systemctl status ollama

# 6. Check it's running
curl http://localhost:11434/api/tags
```

### **Expose to Your App**

Update `chat_web_service.dart` to use your VPS:

```dart
const wsUrl = "ws://your-vps-ip:8000/ws/chat?token=$token";
```

### **Firewall Rules**

```bash
# Allow only your app to access Ollama
sudo ufw allow from YOUR_APP_IP to any port 11434
sudo ufw allow 8000/tcp  # FastAPI backend
```

---

## 💰 **Cost Analysis: Ollama vs Hugging Face**

### **Ollama Approach**
- Initial: $0 (local) or $5-10/mo (VPS)
- Per request: $0
- Unlimited users: ✅
- Total for 100 users, 10,000 requests: **$5-10/month**

### **Hugging Face Approach**
- Free tier: $0
- Scale to 100 users: Eventually need paid tier
- Total for 100 users, 10,000 requests: **$20-50/month**

### **Winner**: Ollama (for scale)

---

## 🆘 **Troubleshooting**

### **Issue: "Cannot connect to Ollama"**
```bash
# Make sure Ollama is running
ollama serve

# Check if it's listening
curl http://localhost:11434/api/tags
```

### **Issue: "model.Pulled but still not found"**
```bash
# List installed models
ollama list

# Pull again
ollama pull mistral
```

### **Issue: "Out of memory" on VPS**
```bash
# Check available RAM
free -h

# Try smaller model
ollama pull neural-chat  # 4GB instead of 7GB
```

### **Issue: Slow responses**
```bash
# Check if server is under heavy load
top

# Options:
# 1. Use smaller model (orca-mini)
# 2. Upgrade VPS RAM
# 3. Increase timeout in llm_service.py
```

---

## 📚 **Resources**

- **Ollama Website**: https://ollama.ai
- **Available Models**: https://ollama.ai/library
- **API Documentation**: https://github.com/ollama/ollama/blob/main/docs/api.md
- **VPS Providers**:
  - DigitalOcean: https://www.digitalocean.com
  - Linode: https://www.linode.com
  - Vultr: https://www.vultr.com
  - AWS: https://aws.amazon.com/ec2

---

## 🚀 **Next Steps**

1. Download Ollama from https://ollama.ai
2. Run `ollama pull mistral`
3. Replace `server/services/llm_service.py` with Ollama code above
4. Restart your backend
5. Test with Flutter app

**Congratulations! Now you have unlimited AI requests with zero API costs! 🎉**
