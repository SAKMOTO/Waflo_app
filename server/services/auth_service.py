from supabase import create_client, Client
from config import Settings
from typing import Optional
from datetime import datetime, date
import json

settings = Settings()


class AuthService:
    """Handle authentication and rate limiting with Supabase"""

    def __init__(self):
        try:
            self.supabase: Client = create_client(
                settings.SUPABASE_URL,
                settings.SUPABASE_SERVICE_ROLE_KEY
            )
            print("✅ Supabase client initialized")
        except Exception as e:
            print(f"⚠️ Supabase initialization failed: {e}")
            self.supabase = None

    def verify_token(self, token: str) -> Optional[str]:
        """
        Verify JWT token and return user_id
        
        Args:
            token: JWT token from client
            
        Returns:
            user_id if token is valid, None otherwise
        """
        if not self.supabase:
            return None

        try:
            # Verify token with Supabase
            response = self.supabase.auth.get_user(token)
            user_id = response.user.id
            print(f"✅ Token verified for user: {user_id}")
            return user_id
        except Exception as e:
            print(f"❌ Token verification failed: {e}")
            return None

    def get_user_rate_limit(self, user_id: str) -> dict:
        """
        Get rate limit status for user
        
        Args:
            user_id: Supabase user ID
            
        Returns:
            Dict with daily_limit, monthly_limit, requests_today, requests_this_month
        """
        if not self.supabase:
            return self._default_limits()

        try:
            response = self.supabase.table('rate_limits').select('*').eq(
                'user_id', user_id
            ).execute()

            if response.data and len(response.data) > 0:
                data = response.data[0]
                
                # Reset daily counter if new day
                today = date.today()
                last_reset = datetime.fromisoformat(data.get('last_reset_date', str(today))).date()
                
                if last_reset < today:
                    # Reset daily counter
                    self.supabase.table('rate_limits').update({
                        'requests_today': 0,
                        'last_reset_date': str(today),
                    }).eq('user_id', user_id).execute()
                    
                    return {
                        'daily_limit': data.get('daily_limit', 10),
                        'monthly_limit': data.get('monthly_limit', 300),
                        'requests_today': 0,
                        'requests_this_month': data.get('requests_this_month', 0),
                    }
                
                return {
                    'daily_limit': data.get('daily_limit', 10),
                    'monthly_limit': data.get('monthly_limit', 300),
                    'requests_today': data.get('requests_today', 0),
                    'requests_this_month': data.get('requests_this_month', 0),
                }
            else:
                # Create new rate limit entry
                print(f"Creating rate limit entry for user: {user_id}")
                self.supabase.table('rate_limits').insert({
                    'user_id': user_id,
                    'daily_limit': 10,
                    'monthly_limit': 300,
                    'requests_today': 0,
                    'requests_this_month': 0,
                    'last_reset_date': str(date.today()),
                }).execute()
                
                return self._default_limits()

        except Exception as e:
            print(f"⚠️ Could not get rate limit: {e}")
            return self._default_limits()

    def increment_usage(self, user_id: str, tokens_used: int = 1) -> bool:
        """
        Track API usage for user
        
        Args:
            user_id: Supabase user ID
            tokens_used: Number of tokens used (default 1)
            
        Returns:
            True if increment successful, False otherwise
        """
        if not self.supabase:
            return False

        try:
            # Get current limits
            limits = self.get_user_rate_limit(user_id)
            
            # Update counters
            self.supabase.table('rate_limits').update({
                'requests_today': limits['requests_today'] + 1,
                'requests_this_month': limits['requests_this_month'] + 1,
            }).eq('user_id', user_id).execute()
            
            print(f"✅ Usage incremented for user {user_id}")
            return True

        except Exception as e:
            print(f"⚠️ Could not increment usage: {e}")
            return False

    def check_rate_limit(self, user_id: str) -> tuple[bool, str]:
        """
        Check if user can make a request
        
        Args:
            user_id: Supabase user ID
            
        Returns:
            Tuple of (can_proceed: bool, message: str)
        """
        limits = self.get_user_rate_limit(user_id)
        
        # Check daily limit
        if limits['requests_today'] >= limits['daily_limit']:
            remaining_tomorrow = (limits['daily_limit'] - limits['requests_today'])
            return False, f"❌ Daily limit reached ({limits['daily_limit']} requests/day). Try again tomorrow."
        
        # Check monthly limit
        if limits['requests_this_month'] >= limits['monthly_limit']:
            return False, f"❌ Monthly limit reached ({limits['monthly_limit']} requests/month). Limit resets on the 1st."
        
        remaining_today = limits['daily_limit'] - limits['requests_today'] - 1
        return True, f"✅ Request allowed. Remaining today: {remaining_today}"

    def log_api_usage(self, user_id: str, query: str, model_used: str, tokens_used: int = 1) -> bool:
        """
        Log API usage to database for analytics
        
        Args:
            user_id: Supabase user ID
            query: The user's query
            model_used: Which model was used (e.g., "Qwen2.5-72B")
            tokens_used: Approximate tokens used
            
        Returns:
            True if logged successfully
        """
        if not self.supabase:
            return False

        try:
            self.supabase.table('api_usage').insert({
                'user_id': user_id,
                'query': query[:500],  # Truncate long queries
                'model_used': model_used,
                'tokens_used': tokens_used,
            }).execute()
            
            return True
        except Exception as e:
            print(f"⚠️ Could not log usage: {e}")
            return False

    def get_user_stats(self, user_id: str) -> dict:
        """
        Get user statistics
        
        Args:
            user_id: Supabase user ID
            
        Returns:
            Dict with usage stats
        """
        if not self.supabase:
            return {}

        try:
            limits = self.get_user_rate_limit(user_id)
            
            # Get total requests
            usage = self.supabase.table('api_usage').select(
                'count', 
                count='exact'
            ).eq('user_id', user_id).execute()
            
            return {
                'requests_today': limits['requests_today'],
                'daily_limit': limits['daily_limit'],
                'requests_this_month': limits['requests_this_month'],
                'monthly_limit': limits['monthly_limit'],
                'total_requests': usage.count if usage.count else 0,
            }

        except Exception as e:
            print(f"⚠️ Could not get user stats: {e}")
            return {}

    @staticmethod
    def _default_limits() -> dict:
        """Return default rate limits"""
        return {
            'daily_limit': 10,
            'monthly_limit': 300,
            'requests_today': 0,
            'requests_this_month': 0,
        }
