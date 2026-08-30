# Waflo App - Comprehensive Project Analysis

## 📋 Executive Summary

**Waflo** is a modern AI-powered cross-platform application combining:
- **Frontend**: Flutter/Dart for iOS, Android, Web, macOS, Linux, and Windows
- **Backend**: Python FastAPI with WebSocket support for real-time communication
- **AI Integration**: Hugging Face API for LLM responses and image generation
- **Search**: Tavily API for web search with content extraction

---

## 🗂️ Complete Project Structure & File-by-File Analysis

### **1. ROOT CONFIGURATION FILES**

#### **pubspec.yaml** - Flutter/Dart Package Configuration
- **Purpose**: Defines Flutter project metadata and dependencies
- **Key Details**:
  - Project Name: `waflo_app`
  - Version: `1.0.0+1`
  - SDK Requirements: Dart 3.12.2+
  - Not published to pub.dev (private package)
  
**Core Dependencies**:
- `google_fonts: ^8.1.0` - Custom font support
- `lottie: ^3.1.2` - Animated JSON-based animations
- `animated_text_kit: ^4.2.2` - Text animation effects
- `spline_flutter: ^0.0.1` - 3D graphics/spline rendering
- `web_socket_client: ^0.2.1` - WebSocket communication
- `flutter_markdown_plus: ^1.0.12` - Markdown rendering with extensions
- `skeletonizer: ^2.1.3` - Loading skeleton placeholders
- `file_picker: ^11.0.2` - File selection dialogs

**Dev Dependencies**:
- `flutter_lints: ^6.0.0` - Flutter linting rules

#### **analysis_options.yaml** - Dart Linting & Analysis Configuration
- **Purpose**: Configures Dart analyzer for code quality
- Includes Flutter recommended lints from `package:flutter_lints/flutter.yaml`
- Allows customization of lint rules (all currently default)
- No active rules modified (all commented out)

#### **README.md** - Project Documentation
- Comprehensive overview of Waflo as "AI-first, cross-platform workspace"
- Tech badges for Flutter 3.x, Dart 3.x, Python, MIT License
- Executive summary positioning Waflo for AI-assisted workflows
- Architecture overview explaining modular structure
- Tech stack documentation
- Repository structure outline

#### **LICENSE** - MIT License
- Copyright: © 2026 HARUN
- Standard MIT license terms allowing commercial use with attribution

---

### **2. FRONTEND - DART/FLUTTER APPLICATION**

#### **lib/main.dart** - Application Entrypoint
```
├── MyApp (StatelessWidget)
├── Material App Configuration
└── Theme Setup
    ├── Dark theme with AppColors.background
    ├── Font: Google Fonts "Inter" (dark theme)
    ├── Color Scheme: Seed color from submitButton (cyan)
    └── Homepage: HomePage()
```

**Key Features**:
- Removes debug banner
- Sets app title to "Waflo"
- Applies custom dark theme with white text
- Routes to `HomePage` as entry point

---

#### **lib/pages/home_page.dart** - Landing/Search Page
```
Widget Hierarchy:
├── HomePage (StatefulWidget)
├── Scaffold
├── Row Layout (Left-Right)
│   ├── sidebar() - Navigation sidebar
│   ├── Expanded Column (Main Content)
│   │   ├── SearchSection() - Featured on page
│   │   └── Footer (Copyright 2026 Waflo)
│   └── Placeholder (Right side spacing)
└── Lifecycle
    └── initState() - Connects ChatWebService
```

**Purpose**: Main landing page with search interface

**Key Functions**:
- Initializes WebSocket connection via `ChatWebService().connect()`
- Displays centered search bar and tagline
- Bottom footer with copyright text
- Clean three-column layout

---

#### **lib/pages/chat_page.dart** - Chat/Response Display Page
```
Widget Hierarchy:
├── ChatPage (StatelessWidget)
├── Constructor: question (required)
├── Scaffold with Row Layout
├── Left: sidebar()
├── Center: ScrollView Column
│   ├── Question Title (Large, White Text)
│   ├── SourcesSection() - Search results display
│   ├── ImageGallery() - Web images (conditional)
│   ├── Generated Image Display (conditional, base64)
│   └── AnswerSection() - Streamed LLM response
├── Bottom: ChatInputBar (replacePage: true)
└── Right: Placeholder spacing
```

**Purpose**: Display AI-generated responses with sources, images, and follow-up interface

**Key Features**:
- Shows user's original question as large header
- Displays relevant sources found by search
- Shows web images fetched during search
- Shows AI-generated image if image generation was triggered
- Streams answer from backend in real-time
- Allows new queries without leaving chat
- Includes sidebar for navigation

---

#### **lib/theme/colors.dart** - Centralized Color System
```dart
Color Scheme:
├── background = RGB(25, 26, 26) - Dark background
├── sideNav = RGB(32, 34, 34) - Sidebar background
├── searchBar = RGB(32, 34, 34) - Search input background
├── searchBarBorder = RGB(60, 63, 64) - Search border
├── iconGrey = #909090 - Icon color
├── textGrey = #AAAAAA - Muted text
├── footerGrey = #737373 - Footer text
├── proButton = RGB(47, 48, 47) - Hover button
├── cardColor = #262626 - Card backgrounds
├── submitButton = RGB(27, 185, 206) - Cyan/Teal CTA
└── whiteColor = White - Primary text
```

**Purpose**: Single source of truth for all colors, ensuring design consistency

---

#### **lib/widgets/** - Reusable UI Components

##### **side_bar.dart** - Collapsible Navigation Sidebar
```
Structure:
├── sidebar (StatefulWidget)
├── AnimatedContainer (80px → 130px width)
├── State: isCollapse (boolean toggle)
├── Children:
│   ├── Home Icon + Label (animated)
│   ├── SideBarButton (Add)
│   ├── SideBarButton (Search)
│   ├── SideBarButton (Spaces)
│   ├── SideBarButton (Discover)
│   ├── SideBarButton (Library)
│   ├── SideBarButton (Settings)
│   └── Toggle Button (arrow left/right)
└── Animations: 150ms transition on collapse/expand
```

**Purpose**: Persistent side navigation with smooth collapse/expand animation

**Interaction**:
- Click arrow to toggle between collapsed (icons only) and expanded (icons + labels)
- All menu items are placeholders (no actual navigation implemented yet)

---

##### **search_bar_button.dart** - Reusable Icon Button
```
Structure:
├── SearchBarButton (StatefulWidget)
├── Properties: icon, text, onTap callback
├── State: isHovered (boolean)
├── Styling:
│   ├── Default: Transparent background
│   ├── Hover: AppColors.proButton (dark gray)
│   ├── Icon: appColors.iconGrey
│   └── Text: AppColors.textGrey
└── Behavior: MouseRegion detects hover state
```

**Purpose**: Small interactive button used in search bar for "Focus" and "Attach" actions

---

##### **side_bar_button.dart** - Sidebar Menu Item Component
```
Structure:
├── SideBarButton (StatelessWidget)
├── Properties: isCollapsed, icon, text
├── Conditional Layout:
│   ├── Collapsed: Icon centered
│   └── Expanded: Icon + Label (horizontal)
├── Styling:
│   ├── Icons: White, 25px
│   └── Text: White, Bold, 13px
└── Spacing: 15px padding (horizontal/vertical)
```

**Purpose**: Individual menu item in sidebar with responsive layout

---

##### **chat_input_bar.dart** - Main Search/Chat Input Component
```
Structure:
├── ChatInputBar (StatefulWidget)
├── Property: replacePage (bool)
│   ├── false: Push new ChatPage (stack on top)
│   └── true: Replace current page
├── State Variables:
│   ├── queryController - Text input
│   ├── selectedFileName - File metadata
│   └── selectedFileBase64 - File content (base64 encoded)
├── UI Layout:
│   ├── Container (700px width, cyan border)
│   ├── TextField (Search input)
│   ├── File Display (if attached)
│   ├── Bottom Actions Row:
│   │   ├── SearchBarButton (Focus)
│   │   ├── SearchBarButton (Attach - file picker)
│   │   └── Submit Button (Arrow icon, cyan)
│   └── Border Radius: 40px (pill shape)
├── File Handling:
│   ├── pickFile() - Opens file picker
│   ├── Reads file as bytes
│   ├── Encodes to base64
│   └── Stores filename + base64
└── Submit Logic:
    ├── Validates query or file exists
    ├── Calls ChatWebService.chat()
    ├── Navigates to ChatPage with question
    └── Passes file data if selected
```

**Purpose**: Primary search/chat input interface with file attachment capability

**File Support**:
- Any file type supported by FilePicker
- Automatically encodes to base64
- Sends filename + base64 data to backend

---

##### **search_section.dart** - Landing Page Search Display
```
Structure:
├── SearchSection (StatefulWidget)
├── Column Layout (Center)
├── Tagline Text:
│   ├── Font: IBM Plex Mono
│   ├── Text: "Where knowledge meets WAFLO"
│   ├── Size: 25px, Bold, Monospace
│   └── Letter Spacing: 0.5
└── ChatInputBar (replacePage: false)
```

**Purpose**: Centered hero section on homepage with branded tagline and search input

---

##### **sources_section.dart** - Search Results Display
```
Structure:
├── SourcesSection (StatefulWidget)
├── Streams from: ChatWebService.searchResultStream
├── Header:
│   ├── Icon: source_outlined
│   └── Text: "Sources" (18px, bold)
├── Content:
│   ├── Wrap layout (spacing: 16px)
│   ├── For each search result:
│   │   ├── Container (150px width)
│   │   ├── Card styling (cardColor background)
│   │   ├── Title (bold, 2 lines max, ellipsis)
│   │   ├── URL (gray, 12px, 1 line max, ellipsis)
│   │   └── Padding: 16px
│   └── Loading: Skeletonizer (skeleton placeholders)
└── State:
    ├── isLoading (boolean)
    ├── searchResults (array)
    └── StreamSubscription (cleanup on dispose)
```

**Purpose**: Displays web search results as clickable cards

**Data Flow**:
- Listens to `ChatWebService().searchResultStream`
- Updates when backend sends `search_result` message
- Shows skeleton loaders while fetching
- Each result shows title, URL, and relevance score

---

##### **answer_section.dart** - AI Response Display
```
Structure:
├── AnswerSection (StatefulWidget)
├── Streams from: ChatWebService.contentStream
├── Header:
│   ├── Text: "WAFLO" (20px, bold)
├── Content:
│   ├── Markdown Renderer
│   ├── Support: Code blocks, inline code, links, etc.
│   ├── Code Block Styling:
│   │   ├── Background: AppColors.cardColor
│   │   ├── Border Radius: 10px
│   │   └── Font Size: 16px
│   └── Loading: Skeletonizer while streaming
├── Footer:
│   └── Copy Button (if response ready)
│       ├── Copies response to clipboard
│       ├── Shows snackbar confirmation
│       └── Icon: copy (gray)
└── State:
    ├── fullResponse (accumulates chunks)
    ├── isLoading (boolean)
    └── StreamSubscription (cleanup on dispose)
```

**Purpose**: Displays AI-generated response with streaming capability

**Features**:
- Real-time streaming of response chunks
- Markdown formatting (bold, italic, code, links, lists, etc.)
- Copy-to-clipboard functionality
- Skeleton loading placeholders while response streams

---

##### **image_gallery.dart** - Web Images Display
```
Structure:
├── ImageGallery (StatelessWidget)
├── Property: imageUrls (List<String>)
├── Header:
│   ├── Icon: image
│   └── Text: "Web Images" (16px, bold)
├── Content:
│   ├── ListView (horizontal scroll)
│   ├── For each image:
│   │   ├── ClipRRect (border radius 10px)
│   │   ├── Image.network (120x120px)
│   │   ├── Fit: cover
│   │   └── Error Fallback: Gray box + broken_image icon
│   ├── Height: 120px
│   └── Spacing: 10px between items
└── Visibility:
    └── Returns SizedBox.shrink() if list empty
```

**Purpose**: Displays web images found during search in a horizontal scrollable gallery

**Error Handling**:
- Shows placeholder if image fails to load
- Gracefully handles network errors

---

#### **lib/services/chat_web_service.dart** - WebSocket Communication Service
```
Class: ChatWebService (Singleton Pattern)

Static Instance: _instance (lazy initialization)
Properties:
├── _socket - WebSocket connection
├── Broadcast StreamControllers:
│   ├── _searchResultController - Search results
│   ├── _contentController - Chat responses
│   ├── _imagesController - Web images list
│   └── _generatedImageController - Generated image (base64)
└── Public Streams:
    ├── searchResultStream
    ├── contentStream
    ├── imagesStream
    └── generatedImageStream

Methods:
├── connect()
│   ├── Creates WebSocket: ws://localhost:8000/ws/chat
│   ├── Listens to incoming messages
│   ├── Routes by type:
│   │   ├── 'search_result' → searchResultController
│   │   ├── 'content' → contentController
│   │   ├── 'web_images' → imagesController
│   │   └── 'generated_image' → generatedImageController
│   └── Decodes JSON payloads
│
└── chat(query, fileName?, fileBase64?)
    ├── Creates payload: {query, file_name?, file_base64?}
    ├── Encodes to JSON
    └── Sends via WebSocket
```

**Purpose**: Singleton service managing real-time WebSocket communication

**Message Protocol**:
- **Send**: `{query: string, file_name?: string, file_base64?: string}`
- **Receive Types**:
  - `search_result` → sources with title, url, content, relevance_score
  - `content` → streaming response chunks
  - `web_images` → array of image URLs
  - `generated_image` → base64-encoded image
  - `done` → indicates response complete

---

### **3. BACKEND - PYTHON FASTAPI APPLICATION**

#### **server/config.py** - Configuration Management
```python
Structure:
├── Library: pydantic_settings, BaseSettings
├── Load Environment: load_dotenv()
├── Settings Class:
│   ├── TAVILY_API_KEY (str) - Web search API key
│   └── HF_TOKEN (str) - Hugging Face API token
└── Initialization: Loads from .env file
```

**Purpose**: Environment configuration management using Pydantic

**Environment Variables Required**:
- `TAVILY_API_KEY` - API key for Tavily web search service
- `HF_TOKEN` - Hugging Face API token for LLM and image generation

---

#### **server/main.py** - FastAPI Backend Server
```
Application: FastAPI instance

Global Services:
├── search_service = SearchService()
├── sort_source_service = SortSourceService()
└── llm_service = LLMService()

Endpoints:

1. WebSocket Endpoint: /ws/chat
   ├── Method: websocket_chat_endpoint()
   ├── Lifecycle:
   │   ├── Accept WebSocket connection
   │   ├── Receive JSON from client
   │   ├── Parse: query, file_name, file_base64
   │   ├── Validate (require query OR file)
   │   ├── Process request (multi-step pipeline)
   │   └── Send responses to client
   │
   ├── Processing Pipeline:
   │   ├── Step 1: Web Search
   │   │   └── search_service.web_search(query)
   │   │       └── Returns: {results: [...], images: [...]}
   │   │
   │   ├── Step 2: Source Sorting
   │   │   └── sort_source_service.sort_sources(query, results)
   │   │       └── Returns: Sorted by relevance score
   │   │
   │   ├── Step 3: Route Request
   │   │   ├── Check if image generation request
   │   │   ├── If YES → Use HFRouter
   │   │   └── If NO → Use LLMService
   │   │
   │   ├── Step 4a: Image Generation
   │   │   ├── hf_router.is_image_request(query)
   │   │   ├── Send "Generating image..." status
   │   │   ├── hf_router.generate_image(query)
   │   │   └── Send base64-encoded image
   │   │
   │   └── Step 4b: Text Generation
   │       ├── llm_service.generate_response(query, results, file)
   │       ├── Stream chunks in real-time
   │       └── Each chunk → send_json("content", data)
   │
   ├── Response Messages Sent:
   │   ├── search_result: {type, data: [sources]}
   │   ├── web_images: {type, data: [urls]}
   │   ├── generated_image: {type, data: base64}
   │   ├── content: {type, data: response_chunk}
   │   ├── done: {} (indicates completion)
   │   └── error: {type, data: error_message}
   │
   ├── Error Handling:
   │   ├── WebSocketDisconnect → log disconnect
   │   ├── Generic Exception → send error JSON
   │   └── Finally → close handler
   │
   └── Logging: Print statements at each step (1-10)

2. HTTP Endpoint: POST /chat
   ├── Request Body: ChatBody (query required)
   ├── Processing:
   │   ├── Web search
   │   ├── Sort sources
   │   ├── Generate response
   │   └── Accumulate chunks
   ├── Response: {response: full_text}
   └── Note: Synchronous (blocks until complete)
```

**Purpose**: Main server application handling real-time chat via WebSocket

**Key Features**:
- Real-time streaming responses via WebSocket
- Multi-model routing (text or image generation)
- File attachment support
- Source ranking and deduplication
- Synchronous HTTP endpoint alternative

---

#### **server/pydantic_models/chat_body.py** - Request Model
```python
Class: ChatBody (BaseModel)
├── query: str (required)
└── Purpose: Validates POST /chat request body
```

**Purpose**: Type-safe request validation using Pydantic

---

#### **server/services/search_service.py** - Web Search & Content Extraction
```python
Class: SearchService

Dependencies:
├── TavilyClient - Web search API
├── trafilatura - HTML content extraction
└── Settings - API keys

Method: web_search(query: str) → dict

Process:
├── Step 1: API Call
│   └── tavily_client.search(query, max_results=10, include_images=True)
│   └── Returns: {results: [...], images: [...]}
│
├── Step 2: Content Extraction Loop
│   ├── For each search result:
│   │   ├── Extract: title, url
│   │   ├── Fetch URL: trafilatura.fetch_url(result.url)
│   │   ├── Extract HTML: trafilatura.extract(content)
│   │   │   └── Parameters:
│   │   │       ├── include_comments=False
│   │   │       └── Returns: clean text
│   │   └── Fallback: empty string if extraction fails
│   │
│   └── Build result object:
│       ├── title (string)
│       ├── url (string)
│       └── content (extracted text)
│
├── Step 3: Return Structure
│   ├── results: [
│   │   {
│   │     "title": "...",
│   │     "url": "...",
│   │     "content": "..."
│   │   },
│   │   ...
│   │ ]
│   └── images: [url1, url2, ...]
│
└── Notes:
    ├── Max 10 results per query
    ├── Images fetched separately
    ├── Content = clean, plain text (no HTML)
    └── Handles extraction failures gracefully
```

**Purpose**: Searches web using Tavily API and extracts article content

**Libraries Used**:
- `tavily` - Web search service (Tavily API)
- `trafilatura` - Extracts main content from web pages

---

#### **server/services/sort_source_service.py** - Relevance Ranking
```python
Class: SortSourceService

Model: SentenceTransformer('all-MiniLM-L6-v2')
├── Purpose: Generate embeddings for semantic similarity
├── Download on first use
└── Pre-trained on general similarity tasks

Method: sort_sources(query: str, search_results: List[dict]) → List[dict]

Process:
├── Step 1: Generate Query Embedding
│   └── embedding = encode(query)
│
├── Step 2: For Each Search Result
│   ├── Generate content embedding: encode(result.content)
│   ├── Calculate Cosine Similarity:
│   │   └── similarity = dot(q_embed, r_embed) / (||q_embed|| * ||r_embed||)
│   ├── Add score: res['relevance_score'] = similarity
│   └── Filter: Keep only if similarity > 0.3 (30% threshold)
│
├── Step 3: Sort Results
│   └── Sort by relevance_score (descending)
│
└── Return: Filtered, sorted results

Cosine Similarity Calculation:
├── Range: -1 to 1
├── 1.0 = identical/perfect match
├── 0.0 = orthogonal/unrelated
└── Threshold 0.3 filters low-relevance results
```

**Purpose**: Uses semantic similarity to rank search results by relevance

**Key Features**:
- Pre-trained embeddings (no training needed)
- Fast cosine similarity calculation
- Filters low-relevance results (< 0.3)
- Preserves original metadata (title, url, content)

---

#### **server/services/llm_service.py** - Text Generation
```python
Class: LLMService

Configuration:
├── Client: InferenceClient (Hugging Face API)
├── Model: Qwen/Qwen2.5-72B-Instruct
│   ├── 72B parameter model
│   ├── Instruction-tuned
│   ├── Supports streaming
│   └── Free tier compatible
└── Token Source: HF_TOKEN environment variable

Method: generate_response(query, search_results, file_name?, file_base64?) → Generator[str]

Process:
├── Step 1: Build Context
│   └── Combine all search results:
│       ├── Format: "Source N (URL):\nContent: ..."
│       └── Joined with "\n\n" separator
│
├── Step 2: Build Prompt
│   └── Full prompt template:
│       ├── System message: "Advanced AI assistant"
│       ├── Instructions: "Use ONLY context provided"
│       ├── Context: Concatenated search results
│       ├── Query: User's question
│       └── Guidelines: Cite sources, don't hallucinate
│
├── Step 3: Build Message Content
│   ├── If file attached:
│   │   ├── Determine MIME type
│   │   ├── Add file metadata message
│   │   └── Format: "[User attached file: name.ext of type mime/type]"
│   └── Add prompt text
│
├── Step 4: API Call
│   ├── messages = [{role: "user", content: [...]}]
│   ├── client.chat_completion(
│   │   model="Qwen/Qwen2.5-72B-Instruct",
│   │   messages=messages,
│   │   max_tokens=1024,
│   │   stream=True
│   ├── )
│   └── returns stream of delta objects
│
├── Step 5: Stream Chunks
│   ├── For each chunk in response_stream:
│   │   ├── Extract delta.content
│   │   └── yield chunk text
│   └── Yields incrementally (real-time streaming)
│
└── Error Handling:
    └── Catch HF API errors, yield error message
```

**Purpose**: Generates contextual AI responses using Hugging Face API

**Model Choice**:
- Qwen2.5-72B-Instruct
- Large enough for quality responses
- Instruction-tuned for user queries
- Free tier compatible
- Supports streaming for real-time responses

**Prompt Engineering**:
- Emphasizes using ONLY provided context
- Instructs model to cite sources
- Prevents hallucination via explicit guidelines
- Handles file attachments as metadata

---

#### **server/services/hf_router.py** - Image Generation & Routing
```python
Class: HFRouter

Configuration:
├── Client: InferenceClient (Hugging Face API)
└── Model: black-forest-labs/FLUX.1-dev
    ├── Text-to-image model
    ├── High quality image generation
    └── SOTA model

Method 1: is_image_request(query: str) → bool

Process:
├── Normalize query: query.lower()
├── Keywords: [
│   "generate an image",
│   "create an image",
│   "draw",
│   "make an image",
│   "generate a picture",
│   "create a picture"
│ ]
├── Return: True if ANY keyword in query
└── Simple substring matching

Method 2: generate_image(prompt: str) → str (base64)

Process:
├── Step 1: API Call
│   ├── client.text_to_image(prompt, model="FLUX.1-dev")
│   └── Returns: PIL Image object
│
├── Step 2: Encode to Base64
│   ├── Save to BytesIO buffer as PNG
│   ├── Get bytes: buffer.getvalue()
│   ├── Encode: base64.b64encode(bytes)
│   └── Decode to string: .decode("utf-8")
│
├── Step 3: Return/Error Handling
│   ├── Return: base64 string (no prefix)
│   └── On error: Return None, log error
│
└── Note: Client must decode & display in app

Error Handling:
└── Catch all exceptions, return None gracefully
```

**Purpose**: Routes image generation requests and handles FLUX.1 API

**Keywords Detection**:
- Simple keyword matching (case-insensitive)
- Triggers image generation for user requests
- Falls back to text generation if not matched

**Image Encoding**:
- PNG format (lossless)
- Base64 encoding for transmission
- No content-type prefix (just raw base64)

---

#### **server/test_ws.py** - WebSocket Test Utility
```python
Script: test_ws.py

Purpose: Manual testing of WebSocket endpoint

Flow:
├── Connect to ws://localhost:8000/ws/chat
├── Send JSON: {query: "what is stock"}
├── Listen for messages in loop:
│   ├── Receive and print each message
│   └── Break if '"done"' appears in message
└── Handle exceptions gracefully

Usage:
$ python test_ws.py
Connected
{"type": "search_result", "data": [...]}
...
```

**Purpose**: Simple test client for WebSocket debugging

---

### **4. PLATFORM-SPECIFIC CODE**

#### **android/** - Android Configuration
- `build.gradle.kts` - Kotlin DSL build configuration
- Namespace: `com.example.waflo_app`
- Target SDK: Latest (via flutter.targetSdkVersion)
- Compilation: Java 17
- App ID: `com.example.waflo_app`
- Signing: Debug config for release builds (TODO: Add production signing)

#### **ios/** - iOS Configuration
- `Info.plist` - App metadata (display name: "Waflo App")
- `AppDelegate.swift` - App lifecycle management
- `SceneDelegate.swift` - Scene lifecycle (iOS 13+)
- `Runner.xcworkspace` - Xcode workspace

#### **web/** - Web Platform
- `index.html` - Entry HTML with Flutter bootstrap script
- `manifest.json` - PWA manifest
- `favicon.png` - Favicon
- Metadata: Mobile web app capable

#### **windows/, macos/, linux/** - Desktop Platforms
- `CMakeLists.txt` - Build configuration (C++)
- Native runner code for desktop platforms
- Generated plugin registrants

---

### **5. BUILD & TESTING**

#### **test/widget_test.dart** - Widget Test Suite
```
Test: Counter increments smoke test

Lifecycle:
├── Build MyApp widget
├── Verify counter displays "0"
├── Verify "+1" text not present
├── Tap add button
├── Trigger frame
├── Verify counter displays "1"
└── Verify "0" no longer visible

Status: Basic smoke test (not comprehensive)
Note: This test doesn't match current app functionality
```

**Purpose**: Basic widget testing template

**Current State**:
- Outdated (references counter app, not chat app)
- Needs update to test actual chat functionality
- Example: Should test SearchSection, ChatInputBar widgets

---

## 🔄 Data Flow Architecture

### **User Query Flow**

```
┌─────────────────────────────────────────────────────────────────┐
│                      FLUTTER CLIENT                              │
└─────────────────────────────────────────────────────────────────┘

User Types Query
        ↓
ChatInputBar._submit()
        ↓
ChatWebService.chat(query, file?)
        ↓
WebSocket.send({ query, file_name?, file_base64? })
        ↓

┌─────────────────────────────────────────────────────────────────┐
│                    PYTHON BACKEND                                │
└─────────────────────────────────────────────────────────────────┘

main.py: websocket_chat_endpoint()
        ↓
SearchService.web_search(query)  ──→ Tavily API
        ↓
        ├─→ trafilatura extracts content
        └─→ Returns {results, images}
        ↓
SortSourceService.sort_sources(query, results)
        ↓
        ├─→ Generate embeddings (SentenceTransformer)
        ├─→ Calculate similarity scores
        └─→ Filter & sort by relevance
        ↓
[BRANCH] Check if image request?
        ├─→ YES: HFRouter.generate_image(query)
        │          └─→ FLUX.1-dev (Hugging Face)
        │          └─→ Returns base64 image
        │
        └─→ NO: LLMService.generate_response()
                 └─→ Build prompt with context
                 └─→ Stream from Qwen2.5-72B

Send responses via WebSocket:
        ├─→ search_result (sources)
        ├─→ web_images (URLs)
        ├─→ generated_image (base64) OR
        ├─→ content (streamed response chunks)
        └─→ done (completion signal)

┌─────────────────────────────────────────────────────────────────┐
│                      FLUTTER CLIENT                              │
└─────────────────────────────────────────────────────────────────┘

ChatWebService streams route messages:
        ↓
SourcesSection listens → searchResultStream
ImageGallery listens → imagesStream
        (if web_images received)
AnswerSection listens → contentStream
        (accumulates chunks)
        ↓
Navigate to ChatPage with question
Display all results in real-time
```

---

## 🔌 External API Integrations

### **Tavily API** - Web Search
- **Endpoint**: Cloud API (no local server)
- **Function**: Search internet for relevant sources
- **Returns**: {results: [{title, url, ...}], images: [urls]}
- **Config**: TAVILY_API_KEY in .env
- **Used In**: SearchService.web_search()

### **Hugging Face API** - AI Models
- **Endpoint**: Cloud inference endpoint
- **Models Used**:
  1. Qwen/Qwen2.5-72B-Instruct (text generation)
  2. black-forest-labs/FLUX.1-dev (image generation)
  3. all-MiniLM-L6-v2 (embeddings for local sorting)
- **Config**: HF_TOKEN in .env
- **Used In**: LLMService, HFRouter

### **trafilatura** - Content Extraction
- **Type**: Python library (local)
- **Function**: Extract main content from HTML pages
- **Process**: Fetch URL → Parse HTML → Extract text
- **Used In**: SearchService.web_search()

### **SentenceTransformers** - Semantic Embeddings
- **Type**: Python library (local)
- **Model**: all-MiniLM-L6-v2
- **Function**: Generate embeddings for similarity matching
- **Used In**: SortSourceService.sort_sources()

---

## 📊 Project Statistics

| Category | Count |
|----------|-------|
| **Dart Files** | 12 |
| **Python Files** | 6 |
| **Platform Targets** | 6 (Web, Android, iOS, Windows, macOS, Linux) |
| **UI Widgets** | 10 |
| **Services** | 5 (Chat, Search, Sort, LLM, HFRouter) |
| **External APIs** | 2 (Tavily, Hugging Face) |
| **Dependencies** | 8 (Flutter) + 4 (Python) |

---

## ⚠️ Current Issues & Observations

### **Code Quality**
1. **Outdated Tests**: `widget_test.dart` references non-existent counter app
2. **TODO Comments**: Android release signing needs production config
3. **No Error Messages**: Generic exception handling in many places
4. **Hardcoded URLs**: WebSocket URL hardcoded to `localhost:8000`
5. **No Input Validation**: File size limits not enforced
6. **Type Safety**: Some dynamic typing in Dart (Map<String, dynamic>)

### **Architecture**
1. **Sidebar Navigation**: Menu items don't navigate anywhere
2. **File Support**: No file type validation or size limits
3. **Image Loading**: No retry logic for failed image loads
4. **Caching**: No response caching (all queries re-search)
5. **Authentication**: No user authentication implemented

### **Performance**
1. **Semantic Similarity**: Full re-encode on every query (no caching)
2. **File Transfers**: No chunking for large files (all base64)
3. **UI Updates**: No pagination for many search results
4. **Memory**: Streams not properly closed in some error paths

### **Security**
1. **API Keys**: Exposed in .env (should use secrets management)
2. **File Upload**: No validation of file contents
3. **WebSocket**: No encryption (ws:// not wss://)
4. **CORS**: Not configured (may cause web platform issues)

---

## 🚀 Development Recommendations

### **Immediate Priorities**
1. Fix WebSocket URL configuration (use environment variable)
2. Add proper error handling and user feedback
3. Update widget tests to match actual app
4. Add file upload size/type validation
5. Implement production API key management

### **Short-term Enhancements**
1. Implement sidebar navigation to actual pages
2. Add response caching to reduce API calls
3. Implement user authentication
4. Add pagination for many results
5. Support file download from sources

### **Long-term Features**
1. Chat history/conversation management
2. User profiles and preferences
3. Advanced search filters
4. Collaborative features
5. Mobile app optimization

---

## 📚 Tech Stack Summary

| Layer | Technology | Version |
|-------|-----------|---------|
| **Frontend** | Flutter/Dart | 3.x |
| **Backend** | Python/FastAPI | - |
| **Real-time** | WebSocket | - |
| **Web Search** | Tavily API | - |
| **LLM** | Qwen2.5-72B (Hugging Face) | - |
| **Image Gen** | FLUX.1-dev (Hugging Face) | - |
| **Embeddings** | all-MiniLM-L6-v2 | - |
| **HTML Extraction** | trafilatura | - |
| **UI Framework** | Material Design 3 | - |
| **Fonts** | Google Fonts | - |
| **State Mgmt** | Streams/StreamControllers | - |

---

## 📝 License & Attribution

- **License**: MIT License
- **Copyright**: © 2026 HARUN
- **Repository**: Waflo_app (SAKMOTO/Waflo_app)
- **Branch**: main (default)
