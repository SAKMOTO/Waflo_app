# 🚀 Waflo App - Quick Start (Production Ready)

## 📌 **What We Just Solved**

✅ **Shared API Token Problem** - Now each user gets rate-limited individually
✅ **No Authentication** - Supabase login/signup added
✅ **No User Tracking** - Database tracks all users & usage
✅ **Production Ready** - Secure, scalable, cost-effective

---

## ⚡ **Quick Start: 6 Easy Steps**

### **Step 1: Supabase Setup (5 minutes)**

1. Go to https://supabase.com → "New Project"
2. Fill in:
   - Project Name: `waflo-app`
   - Password: Generate strong one
   - Region: Closest to you
   - Pricing: **Free**
3. Wait for project to create
4. Go to Settings → API
5. Copy these keys:
   - `Project URL` → `SUPABASE_URL`
   - `Publishable Key` → `SUPABASE_PUBLISHABLE_KEY`
   - `Secret Key` → `SUPABASE_SECRET_KEY`
   - `JWKS URL` → `SUPABASE_JWKS_URL`

### **Step 2: Create Database Tables (2 minutes)**

1. In Supabase dashboard → SQL Editor → New Query
2. Copy and paste code from [PRODUCTION_SETUP.md](PRODUCTION_SETUP.md) → "Step 1.3"
3. Click "Run"
4. Done! ✅

### **Step 3: Install Supabase Server SDK (2 minutes)**

```bash
# In server/ folder
cd /workspaces/Waflo_app/server

# Install Supabase server package
pip install supabase
```

### **Step 4: Update Backend (.env) (1 minute)**

```bash
# Copy template
cp .env.example .env

# Edit .env and fill in ALL these values:
TAVILY_API_KEY=your_tavily_key
HF_TOKEN=your_hugging_face_token

# From Supabase Dashboard (Step 1):
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
SUPABASE_SECRET_KEY=sb_secret_...
SUPABASE_JWKS_URL=https://xxxxx.supabase.co/auth/v1/.well-known/jwks.json
```

⚠️ **NEVER** commit `.env` to Git!

### **Step 5: Update Flutter (5 minutes)**

```bash
flutter pub add supabase_flutter
flutter pub add shared_preferences
```

Replace `lib/main.dart` with code from [PRODUCTION_SETUP.md](PRODUCTION_SETUP.md) → Step 2.2

Login page already created: `lib/pages/auth/login_page.dart` ✅

Update `lib/services/chat_web_service.dart` with JWT code from [PRODUCTION_SETUP.md](PRODUCTION_SETUP.md) → Step 4

---

## 🎬 **Step 6: Run & View Your App**

### **Option 1: Web Browser (START HERE)**

```bash
# Terminal 1: Start Backend
cd /workspaces/Waflo_app/server
pip install -r requirements.txt
python main.py

# Wait for: "Uvicorn running on http://127.0.0.1:8000"

# Terminal 2: Start Flutter Web
cd /workspaces/Waflo_app
flutter run -d chrome

# Automatically opens in Chrome/Firefox!
```

**You'll see:**
- ✅ Login/Signup screen first
- ✅ After login → Search interface  
- ✅ Tagline: "Where knowledge meets WAFLO"
- ✅ Search bar in center
- ✅ Sidebar navigation

### **Option 2: Mobile Emulator**

```bash
flutter run -d emulator  # Android
flutter run -d iphone    # iOS (macOS only)
```

### **Option 3: Desktop**

```bash
flutter run -d windows   # Windows
flutter run -d macos     # macOS
flutter run -d linux     # Linux
```

### **Option 4: Web Server**

```bash
flutter run -d web-server
# Then visit: http://localhost:5000
```

---

## ✅ **Complete Test Checklist (5 minutes)**

### **Phase 1: Sign Up**
```
☐ App shows Login page
☐ Click "Don't have account? Sign Up"
☐ Enter: test@example.com
☐ Enter password: password123
☐ Click "Sign Up"
☐ See: "Sign up successful! Check your email."
```

### **Phase 2: Login**
```
☐ Click "Already have account? Login"
☐ Enter same email/password
☐ Click "Login"
☐ Redirects to HomePage (search page)
☐ See tagline: "Where knowledge meets WAFLO"
```

### **Phase 3: Search**
```
☐ Type in search: "What is Flutter?"
☐ Click submit button (arrow)
☐ Page navigates to ChatPage
☐ Shows your question as title
☐ Shows "Sources" section with cards
☐ Shows "Web Images" gallery
☐ Shows "WAFLO" section with AI response
☐ Response streams in real-time
```

### **Phase 4: Rate Limiting**
```
☐ Make 1st search → Works ✅
☐ Make 2nd search → Works ✅
☐ Make 3rd-10th → All work ✅
☐ Make 11th search → Error message:
   "Daily limit reached (10 requests/day)"
   
This proves rate limiting works! 🎉
```

**ALL CHECKMARKS = Production Ready! 🚀**

---

## 📊 **What to Expect**

### **Performance**
```
Login:              ~1 second
Search response:    ~3-5 seconds
Rate limit error:   Instant
Page navigation:    ~1 second
```

### **Total Setup Time**
```
Step 1-2: 7 mins (Supabase + Database)
Step 3-4: 3 mins (Backend setup)
Step 5:   5 mins (Flutter)
Step 6:   5 mins (Run & test)
────────────────────────────
TOTAL:    20 minutes to production! ✅
```

---

## 🐛 **Troubleshooting**

### **"Connection Refused" or WebSocket Error**
```
Error: Failed to connect to ws://localhost:8000/ws/chat

Fix:
1. Terminal 1 running? python main.py
2. Check output: "Uvicorn running on http://127.0.0.1:8000"
3. Restart both terminals
```

### **"Invalid Token" Error**
```
Error: Invalid or expired token

Fix:
1. Check .env has correct SUPABASE_SECRET_KEY
2. Not SUPABASE_PUBLISHABLE_KEY (that's public)
3. Restart backend
```

### **"Cannot find supabase_flutter"**
```
Error: Package not found

Fix:
flutter clean
flutter pub get
flutter run -d chrome
```

### **"Port 8000 already in use"**
```
Error: Address already in use

Fix:
# Find what's using it:
lsof -i :8000

# Kill it:
kill -9 <PID>
```

### **"Database connection failed"**
```
Error: Cannot connect to Supabase

Fix:
1. Check SUPABASE_URL in .env
2. Should look like: https://xxxxx.supabase.co
3. Check SECRET key is correct (not public key)
```

---

## 🔑 **3 API Options** (Choose One)

### **Option A: Hugging Face (Quick, Free, Limited)** ⭐ CURRENT
- ✅ No setup needed (you already have token)
- ✅ Works immediately
- ⚠️ Hits rate limits at ~50 users
- 💰 Free

**Use if**: Testing, small user base (<50)

### **Option B: Ollama Local (Advanced, Unlimited)**
- ✅ Unlimited requests
- ✅ Full privacy (runs locally)
- ✅ $5-10/month cost only
- ⚠️ Slightly slower (5s vs 2s)
- 💰 Free + $5-10/mo VPS

**Use if**: Hit rate limits, care about privacy

**Setup** (10 minutes):
```bash
# 1. Download Ollama from https://ollama.ai
# 2. Run: ollama serve
# 3. In another terminal: ollama pull mistral
# 4. Replace llm_service.py code from OLLAMA_SETUP.md
```

### **Option C: Custom Model (Enterprise)**
- ✅ Full control & customization
- ⚠️ Weeks of development
- ⚠️ $200+/month
- 💰 Expensive

**Use if**: 1000+ users, fully funded, need competitive advantage

---

## 💰 **Cost Breakdown**

| Component | Free Tier | When to Upgrade |
|-----------|-----------|-----------------|
| **Supabase** | $0 (50K users) | $25+/mo (at 50K) |
| **Hugging Face** | $0 (limited) | $20+/mo (at scale) |
| **Tavily** | $0 (1K/month) | $20+/mo (more searches) |
| **Ollama (Optional)** | $0 | $5-10/mo (VPS) |
| **TOTAL** | **$0/month** | **$20-50+/month** |

---

## ✨ **Success Indicators**

All working when you see:
```
✅ Login/Signup page appears
✅ Can create new account with email
✅ Can login with email/password
✅ HomePage appears after login
✅ Can type in search bar
✅ Submit button is responsive
✅ ChatPage appears with your question
✅ Sources display with titles & URLs
✅ WAFLO response streams in real-time
✅ 11th search shows rate limit error
✅ No crashes or error pages
✅ Sidebar navigation appears
```

**Got ALL of these? You're production-ready! 🎉**

---

## 📱 **Multi-Terminal Setup (Copy-Paste Ready)**

```bash
# ===== TERMINAL 1 =====
cd /workspaces/Waflo_app/server
pip install -r requirements.txt
python main.py

# Wait for: "Uvicorn running on http://127.0.0.1:8000"

# ===== TERMINAL 2 =====
cd /workspaces/Waflo_app
flutter run -d chrome

# Wait for app to open in browser automatically!

# ===== TERMINAL 3 (Optional) =====
# Monitor Supabase (in browser):
# https://supabase.com/dashboard → Your Project
# Watch API_USAGE & RATE_LIMITS tables update live!
```

---

## 🚀 **Next Steps After Verification**

### **Ready to Deploy?**

1. **Backend Deployment**
   - Railway: https://railway.app (easiest)
   - Heroku: https://www.heroku.com
   - Render: https://render.com
   - See [PRODUCTION_SETUP.md](PRODUCTION_SETUP.md) for details

2. **Frontend Deployment**
   - Firebase Hosting: `firebase deploy`
   - Netlify: Connect GitHub
   - Vercel: `vercel --prod`

3. **Database**
   - Already on Supabase (no setup needed!)
   - Scales to 50,000+ users free tier

---

## 🔑 **Key Files**

✅ `lib/pages/auth/login_page.dart` - Auth UI
✅ `server/services/auth_service.py` - Backend auth
✅ `server/config.py` - Supabase config
✅ `.env.example` - Template
✅ `lib/services/chat_web_service.dart` - WebSocket JWT

---

## 📚 **More Info**

- **Complete Setup**: [PRODUCTION_SETUP.md](PRODUCTION_SETUP.md)
- **API Options**: [OPTIONS_COMPARISON.md](OPTIONS_COMPARISON.md)
- **Self-Hosted AI**: [OLLAMA_SETUP.md](OLLAMA_SETUP.md)
- **Supabase Docs**: https://supabase.com/docs
- **Flutter Docs**: https://flutter.dev/docs

---

**Ready? Start Terminal 1 → Terminal 2 → Test! 🚀**

**Questions? Check Troubleshooting above or see detailed guides.**

---

**You're production-ready! Launch with confidence! 🎉**
