# 🎯 **HOW TO SEE YOUR APP RUNNING - Quick Visual Guide**

## **Right Now, Follow These 3 Steps:**

---

## **STEP 1️⃣: Start Backend (Terminal 1)**

```bash
cd /workspaces/Waflo_app/server
pip install -r requirements.txt
python main.py
```

**Wait for this message:**
```
✅ INFO:     Uvicorn running on http://127.0.0.1:8000
```

---

## **STEP 2️⃣: Start Flutter App (Terminal 2)**

```bash
cd /workspaces/Waflo_app
flutter run -d chrome
```

**Chrome will open automatically!**

---

## **STEP 3️⃣: Test in Browser**

```
1. Sign up: test@example.com / password123
   ↓
2. Click "Sign Up"
   ↓
3. Login with same credentials
   ↓
4. See HomePage with search bar
   ↓
5. Type: "What is Python?"
   ↓
6. Click submit →
   ↓
7. ChatPage appears with:
   ✅ Your question as title
   ✅ Sources (web search results)
   ✅ Web images
   ✅ AI response from Waflo
```

---

## **🎉 SUCCESS!**

You should see:

```
┌─────────────────────────────────┐
│                                 │
│  WAFLO                          │
│  (on search page)               │
│                                 │
│  "What is Python?"              │
│  (after searching)              │
│                                 │
│  + Sources                      │
│  + Images                       │
│  + AI Response                  │
│                                 │
└─────────────────────────────────┘
```

---

## **🧪 Test Rate Limiting**

Make 11 searches → 11th one will say:
```
"Daily limit reached (10 requests/day)"
```

This proves rate limiting works! ✅

---

## **🐛 Common Issues**

| Issue | Solution |
|-------|----------|
| **Port 8000 in use** | `lsof -i :8000` then `kill -9 <PID>` |
| **Backend won't start** | Check `python main.py` is in `/server` folder |
| **App won't load** | Make sure backend terminal shows "Uvicorn running" |
| **Login fails** | Check `.env` has correct Supabase keys |
| **App already running** | Kill old instances: `flutter clean` |

---

## **📱 Alternative Platforms**

### **Mobile Emulator**
```bash
flutter run -d emulator  # Android
```

### **Desktop**
```bash
flutter run -d windows   # Windows
flutter run -d macos     # macOS  
flutter run -d linux     # Linux
```

### **Web Server Mode**
```bash
flutter run -d web-server
# Visit: http://localhost:5000
```

---

## **✅ Full Setup Was:**

- Step 1: Supabase account → ✅ Done
- Step 2: Database tables → ✅ Done
- Step 3: Install `pip install supabase` → ✅ Done
- Step 4: Update `.env` → ✅ You do this
- Step 5: Update Flutter → ✅ You do this
- Step 6: Run & Test → 👈 **YOU ARE HERE**

---

## **🚀 After It's Working:**

1. Deploy backend (Railway/Heroku)
2. Deploy frontend (Firebase/Netlify)
3. Point frontend to production backend URL
4. Launch! 🎉

See [PRODUCTION_SETUP.md](./PRODUCTION_SETUP.md) for deployment details.

---

**👉 Ready? Open 2 terminals and start Step 1 above! ⬆️**
