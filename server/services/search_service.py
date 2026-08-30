from tavily import TavilyClient
from config import Settings
import trafilatura



settings = Settings()

# Initialize Tavily client only if API key is available
tavily_client = None
if settings.TAVILY_API_KEY and settings.TAVILY_API_KEY != "dummy_key_for_testing":
    try:
        tavily_client = TavilyClient(api_key=settings.TAVILY_API_KEY)
    except Exception as e:
        print(f"Failed to initialize Tavily client: {e}")





class SearchService:
    def  web_search(self,query : str):
        # If Tavily is not available, return empty results
        if tavily_client is None:
            print("Tavily client not available - search disabled")
            return {
                "results": [],
                "images": []
            }
        
        resluts=[]
        try:
            response = tavily_client.search(query, max_results=10, include_images=True)
            search_results = response.get('results',[])
            images = response.get('images', [])

            for result in search_results:
               downloaded = trafilatura.fetch_url(result.get('url'))
               content =trafilatura.extract(downloaded,include_comments=False)

               if content is None:
                  content = ""
           
           
               resluts.append(
                   {
                       "title": result.get("title",""),
                       "url": result.get("url"),
                       "content": content or "",
                   }
               )


            return {
                "results": resluts,
                "images": images
            }
        except Exception as e:
            print(f"Search error: {e}")
            return {
                "results": [],
                "images": []
            }
