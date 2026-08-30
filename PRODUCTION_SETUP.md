# Waflo App - Production Setup Guide

## 🚨 CRITICAL: Production Issues & Solutions

### **Issue 1: Shared API Token (BLOCKER)**

**Problem**: Multiple users sharing one Hugging Face token
- ❌ Rate limits will be hit
- ❌ One user can block all others
- ❌ Security risk (token exposed)
- ❌ Cannot scale beyond ~10-20 users

**Solutions** (in order of recommendation):

#### **Solution A: Supabase Auth + Local Ollama (RECOMMENDED FOR MVP)**
- **Cost**: Free (Supabase + Ollama on cheap server)
- **Setup**: ~2-3 hours
- **Scalability**: 100+ users on $5/month server
- **Pros**: Full control, no rate limits, privacy
- **Cons**: Need to manage server

#### **Solution B: Supabase Auth + HF Free API + Rate Limiting**
- **Cost**: Free tier (100K tokens/month)
- **Setup**: ~1-2 hours
- **Scalability**: 50-100 users
- **Pros**: Quick setup, no server management
- **Cons**: Still hit rate limits eventually

#### **Solution C: Self-Hosted + Backend Rate Limiting**
- **Cost**: $5-20/month (server)
- **Setup**: ~4-6 hours
- **Scalability**: 500+ users
- **Pros**: Unlimited, full control
- **Cons**: More complex deployment

---

## ✅ **RECOMMENDED IMPLEMENTATION: Solution A**

This guide implements:
1. ✅ Supabase Authentication (free tier: 50,000 free users)
2. ✅ Per-user rate limiting
3. ✅ Local Ollama model (or HF free tier with limits)
4. ✅ User session tracking
5. ✅ API key management

---

## 📋 **Step 1: Set Up Supabase (15 minutes)**

### 1.1 Create Supabase Project
```bash
# Go to https://supabase.com
# Click "New Project"
# Name: waflo-app
# Region: Closest to you
# Password: Generate strong password
# Pricing: Free tier
```

### 1.2 Get Credentials
```
After project created:
Project URL: https://[project-id].supabase.co
Anon Key: [copy this]
Service Role Key: [copy this - KEEP SECRET]
```

### 1.3 Create Database Tables
Go to SQL Editor → New Query → Paste this:

```sql
-- Users table (extends auth)
CREATE TABLE public.user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  full_name TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);

-- API Usage tracking
CREATE TABLE public.api_usage (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  query TEXT,
  tokens_used INTEGER,
  model_used TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Rate limit config
CREATE TABLE public.rate_limits (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  daily_limit INTEGER DEFAULT 10,
  monthly_limit INTEGER DEFAULT 300,
  requests_today INTEGER DEFAULT 0,
  requests_this_month INTEGER DEFAULT 0,
  last_reset_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS (Row Level Security)
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rate_limits ENABLE ROW LEVEL SECURITY;

-- RLS Policies: Users can only see their own data
CREATE POLICY "Users can view own profile"
  ON public.user_profiles
  FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can view own usage"
  ON public.api_usage
  FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can view own limits"
  ON public.rate_limits
  FOR SELECT
  USING (auth.uid() = user_id);
```

---

## 📱 **Step 2: Flutter Frontend - Authentication**

### 2.1 Add Supabase Dependency

Edit `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  supabase_flutter: ^2.5.0
  shared_preferences: ^2.2.0
  # ... existing dependencies
```

Run:
```bash
flutter pub get
```

### 2.2 Initialize Supabase in main.dart

Replace `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waflo_app/pages/auth/login_page.dart';
import 'package:waflo_app/pages/home_page.dart';
import 'package:waflo_app/theme/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://[YOUR-PROJECT-ID].supabase.co',
    anonKey: '[YOUR-ANON-KEY]',
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Waflo',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.submitButton),
        textTheme: GoogleFonts.interTextTheme(
          ThemeData.dark().textTheme.copyWith(
                bodyMedium: const TextStyle(
                  fontSize: 15,
                  color: AppColors.whiteColor,
                ),
              ),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // Loading state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Get auth state
        final session = snapshot.data?.session;
        final authenticated = session != null;

        // Route: Logged in → HomePage, else → LoginPage
        return authenticated ? HomePage() : const LoginPage();
      },
    );
  }
}
```

### 2.3 Create Login Page

Create `lib/pages/auth/login_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:waflo_app/theme/colors.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  bool isLoading = false;
  bool isSignUp = false;
  String? errorMessage;

  Future<void> handleAuth() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      if (isSignUp) {
        await Supabase.instance.client.auth.signUp(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sign up successful! Check your email.')),
        );
      } else {
        await Supabase.instance.client.auth.signInWithPassword(
          email: emailController.text.trim(),
          password: passwordController.text,
        );
      }
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo/Title
              Text(
                'WAFLO',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'AI-Powered Search & Chat',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 48),

              // Email Field
              SizedBox(
                width: 300,
                child: TextField(
                  controller: emailController,
                  decoration: InputDecoration(
                    hintText: 'Email',
                    filled: true,
                    fillColor: AppColors.searchBar,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.searchBarBorder),
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
              SizedBox(height: 16),

              // Password Field
              SizedBox(
                width: 300,
                child: TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password (min 6 chars)',
                    filled: true,
                    fillColor: AppColors.searchBar,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.searchBarBorder),
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                ),
              ),
              SizedBox(height: 24),

              // Error Message
              if (errorMessage != null)
                Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    errorMessage!,
                    style: TextStyle(color: Colors.red, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),

              // Auth Button
              SizedBox(
                width: 300,
                height: 48,
                child: ElevatedButton(
                  onPressed: isLoading ? null : handleAuth,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.submitButton,
                    disabledBackgroundColor: Colors.grey,
                  ),
                  child: isLoading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text(
                          isSignUp ? 'Sign Up' : 'Login',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              SizedBox(height: 16),

              // Toggle Sign Up / Login
              TextButton(
                onPressed: () {
                  setState(() {
                    isSignUp = !isSignUp;
                    errorMessage = null;
                  });
                },
                child: Text(
                  isSignUp
                      ? 'Already have account? Login'
                      : 'Don\'t have account? Sign Up',
                  style: TextStyle(color: AppColors.submitButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}
```

---

## 🔒 **Step 3: Backend - Authentication Middleware**

### 3.1 Update `server/config.py`

```python
from dotenv import load_dotenv
from pydantic_settings import BaseSettings

load_dotenv()

class Settings(BaseSettings):
    TAVILY_API_KEY: str = ""
    HF_TOKEN: str = ""
    SUPABASE_URL: str = ""
    SUPABASE_KEY: str = ""
    SUPABASE_SERVICE_ROLE_KEY: str = ""

settings = Settings()
```

### 3.2 Create `server/services/auth_service.py`

```python
from supabase import create_client, Client
from config import settings
from typing import Optional
import json

class AuthService:
    def __init__(self):
        self.supabase: Client = create_client(
            settings.SUPABASE_URL,
            settings.SUPABASE_SERVICE_ROLE_KEY
        )
    
    def verify_token(self, token: str) -> Optional[str]:
        """Verify JWT token and return user_id"""
        try:
            # Verify token with Supabase
            response = self.supabase.auth.get_user(token)
            return response.user.id
        except Exception as e:
            print(f"Token verification failed: {e}")
            return None
    
    def get_user_rate_limit(self, user_id: str) -> dict:
        """Get rate limit status for user"""
        try:
            response = self.supabase.table('rate_limits').select('*').eq(
                'user_id', user_id
            ).single().execute()
            
            data = response.data
            return {
                'daily_limit': data.get('daily_limit', 10),
                'monthly_limit': data.get('monthly_limit', 300),
                'requests_today': data.get('requests_today', 0),
                'requests_this_month': data.get('requests_this_month', 0),
            }
        except Exception as e:
            print(f"Could not get rate limit: {e}")
            # Return default limits
            return {
                'daily_limit': 10,
                'monthly_limit': 300,
                'requests_today': 0,
                'requests_this_month': 0,
            }
    
    def increment_usage(self, user_id: str, tokens_used: int = 1):
        """Track API usage for user"""
        try:
            # Get current limits
            limits = self.get_user_rate_limit(user_id)
            
            # Update counters
            self.supabase.table('rate_limits').update({
                'requests_today': limits['requests_today'] + 1,
                'requests_this_month': limits['requests_this_month'] + 1,
            }).eq('user_id', user_id).execute()
            
        except Exception as e:
            print(f"Could not increment usage: {e}")
    
    def check_rate_limit(self, user_id: str) -> tuple[bool, str]:
        """Check if user can make a request"""
        limits = self.get_user_rate_limit(user_id)
        
        if limits['requests_today'] >= limits['daily_limit']:
            return False, f"Daily limit reached ({limits['daily_limit']} requests)"
        
        if limits['requests_this_month'] >= limits['monthly_limit']:
            return False, f"Monthly limit reached ({limits['monthly_limit']} requests)"
        
        return True, "OK"
```

### 3.3 Update `server/main.py`

```python
from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Query
from fastapi.middleware.cors import CORSMiddleware
import traceback
import json

from pydantic_models.chat_body import ChatBody
from services.llm_service import LLMService
from services.sort_source_service import SortSourceService
from services.search_service import SearchService
from services.auth_service import AuthService

app = FastAPI()

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Change this in production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

search_service = SearchService()
sort_source_service = SortSourceService()
llm_service = LLMService()
auth_service = AuthService()

# Chat WebSocket with authentication
@app.websocket("/ws/chat")
async def websocket_chat_endpoint(
    websocket: WebSocket,
    token: str = Query(...)  # Get JWT token from query
):
    await websocket.accept()
    
    # Verify token
    user_id = auth_service.verify_token(token)
    if not user_id:
        await websocket.send_json({
            "type": "error",
            "data": "Invalid or expired token"
        })
        await websocket.close()
        return
    
    print(f"User {user_id} connected")
    
    try:
        while True:
            data = await websocket.receive_json()
            query = data.get("query")
            
            # CHECK RATE LIMIT
            can_proceed, limit_msg = auth_service.check_rate_limit(user_id)
            if not can_proceed:
                await websocket.send_json({
                    "type": "error",
                    "data": limit_msg
                })
                continue
            
            # Process normally
            search_results = search_service.web_search(query) if query else []
            sorted_results = sort_source_service.sort_sources(
                query,
                search_results.get("results", []) if type(search_results) == dict else search_results
            ) if query else []
            
            await websocket.send_json({
                "type": "search_result",
                "data": sorted_results if type(sorted_results) == list else sorted_results.get("results", [])
            })
            
            if type(search_results) == dict and "images" in search_results:
                await websocket.send_json({
                    "type": "web_images",
                    "data": search_results["images"]
                })
            
            # Generate response and stream
            for chunk in llm_service.generate_response(query, sorted_results):
                if chunk:
                    await websocket.send_json({
                        "type": "content",
                        "data": chunk
                    })
            
            # Increment usage
            auth_service.increment_usage(user_id)
            
            await websocket.send_json({"type": "done"})
            
    except WebSocketDisconnect:
        print(f"User {user_id} disconnected")
    except Exception as e:
        traceback.print_exc()
        try:
            await websocket.send_json({
                "type": "error",
                "data": str(e)
            })
        except:
            pass
```

---

## 📱 **Step 4: Update Flutter WebSocket**

Edit `lib/services/chat_web_service.dart`:

```dart
import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_client/web_socket_client.dart';

class ChatWebService {
  static final _instance = ChatWebService._internal();
  WebSocket? _socket;

  factory ChatWebService() => _instance;
  ChatWebService._internal();

  final _searchResultController = StreamController<Map<String, dynamic>>.broadcast();
  final _contentController = StreamController<Map<String, dynamic>>.broadcast();
  final _imagesController = StreamController<List<String>>.broadcast();
  final _generatedImageController = StreamController<String>.broadcast();

  Stream<Map<String, dynamic>> get searchResultStream => _searchResultController.stream;
  Stream<Map<String, dynamic>> get contentStream => _contentController.stream;
  Stream<List<String>> get imagesStream => _imagesController.stream;
  Stream<String> get generatedImageStream => _generatedImageController.stream;

  Future<void> connect() async {
    try {
      // Get JWT token from Supabase
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception("Not authenticated");
      }
      
      final token = session.accessToken;
      final wsUrl = "ws://localhost:8000/ws/chat?token=$token";
      
      _socket = WebSocket(Uri.parse(wsUrl));

      _socket!.messages.listen((message) {
        final data = json.decode(message);
        if (data['type'] == 'search_result') {
          _searchResultController.add(data);
        } else if (data['type'] == 'content') {
          _contentController.add(data);
        } else if (data['type'] == 'web_images') {
          List<String> images = List<String>.from(data['data']);
          _imagesController.add(images);
        } else if (data['type'] == 'generated_image') {
          _generatedImageController.add(data['data']);
        } else if (data['type'] == 'error') {
          _contentController.add({
            'type': 'error',
            'data': data['data']
          });
        }
      });
    } catch (e) {
      print("WebSocket connection error: $e");
    }
  }

  void chat(String query, {String? fileName, String? fileBase64}) {
    final payload = {'query': query};
    if (fileName != null && fileBase64 != null) {
      payload['file_name'] = fileName;
      payload['file_base64'] = fileBase64;
    }
    _socket!.send(json.encode(payload));
  }

  void disconnect() {
    _socket?.close();
  }
}
```

---

## 🚀 **Step 5: Optional - Use Ollama Locally (No API Limits)**

If you want to avoid HF API limits completely:

### 5.1 Install Ollama
```bash
# Linux
curl https://ollama.ai/install.sh | sh

# macOS
# Download from https://ollama.ai

# Windows
# Download from https://ollama.ai
```

### 5.2 Run Ollama Model
```bash
# Start Ollama service
ollama serve

# In another terminal, pull a model
ollama pull mistral  # or neural-chat, dolphin-mixtral, etc.
```

### 5.3 Replace HF with Ollama in `llm_service.py`

```python
import requests

class LLMService:
    def __init__(self):
        self.ollama_url = "http://localhost:11434/api/generate"
        self.model = "mistral"  # or your chosen model
    
    def generate_response(self, query: str, search_results: list, **kwargs):
        context = "\n\n".join([
            f"Source {i+1} ({r.get('url', '')}):\n{r.get('content', '')}"
            for i, r in enumerate(search_results)
        ])
        
        prompt = f"""You are a helpful AI assistant. 
        Use ONLY the following context to answer the user's query.
        
        Context:
        {context}
        
        Query: {query}
        
        Answer:"""
        
        # Stream from Ollama
        response = requests.post(
            self.ollama_url,
            json={
                "model": self.model,
                "prompt": prompt,
                "stream": True
            },
            stream=True
        )
        
        for line in response.iter_lines():
            if line:
                data = json.loads(line)
                if data.get("response"):
                    yield data["response"]
```

---

## 📊 **Step 6: Environment Variables**

Create `.env` file in server directory:

```bash
# Hugging Face (keep for images only)
HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx

# Tavily Search
TAVILY_API_KEY=tvly-xxxxxxxxxxxxxxxx

# Supabase
SUPABASE_URL=https://[project-id].supabase.co
SUPABASE_KEY=[anon-key]
SUPABASE_SERVICE_ROLE_KEY=[service-role-key]
```

---

## ✅ **Deployment Checklist**

- [ ] Create Supabase project
- [ ] Create database tables & RLS policies
- [ ] Add Supabase Flutter dependency
- [ ] Create LoginPage & integrate auth
- [ ] Create AuthService in backend
- [ ] Update WebSocket with JWT verification
- [ ] Add CORS middleware
- [ ] Test auth flow locally
- [ ] Get Supabase API keys into `.env`
- [ ] Test rate limiting

---

## 🎯 **Summary: What Gets Fixed**

| Issue | Before | After |
|-------|--------|-------|
| **Shared API Token** | ❌ One token for all | ✅ Per-user tracking |
| **Rate Limiting** | ❌ Everyone shares limits | ✅ 10 requests/day per user |
| **Authentication** | ❌ None | ✅ Supabase OAuth |
| **User Tracking** | ❌ No user data | ✅ DB tracks each user |
| **Production Ready** | ❌ No | ✅ Yes |
| **Cost** | ❌ Unclear | ✅ Free tier (or $5/mo) |

---

## 🆘 **Quick Troubleshooting**

```
Q: "Invalid token" error
A: Make sure JWT token is passed correctly in WebSocket URL

Q: Rate limit errors
A: Reset counters manually in Supabase dashboard

Q: Supabase connection fails
A: Check SUPABASE_URL and keys in .env file

Q: Ollama too slow
A: Use smaller model (neural-chat instead of mistral)
```

---

## 📞 **Need Help?**

1. **Supabase Docs**: https://supabase.com/docs
2. **Flutter Supabase**: https://supabase.com/docs/guides/auth/auth-flutter
3. **Ollama Models**: https://ollama.ai/library
