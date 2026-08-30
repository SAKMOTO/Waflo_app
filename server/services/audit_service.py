import json
import logging
from pathlib import Path
from datetime import datetime
from typing import List, Optional
from pydantic_models.commerce_models import AuditLogEntry

logger = logging.getLogger(__name__)


class AuditService:
    """Service for persistent audit trail storage"""
    
    def __init__(self, audit_dir: str = "audit_logs"):
        self.audit_dir = Path(audit_dir)
        self.audit_dir.mkdir(exist_ok=True)
        
    def _get_audit_file_path(self, task_id: str) -> Path:
        """Get the file path for a specific task's audit log"""
        return self.audit_dir / f"{task_id}.json"
    
    def save_audit_log(self, log_entry: AuditLogEntry) -> bool:
        """Save a single audit log entry to file"""
        try:
            file_path = self._get_audit_file_path(log_entry.task_id)
            
            # Load existing logs
            existing_logs = []
            if file_path.exists():
                try:
                    with open(file_path, 'r') as f:
                        existing_logs = json.load(f)
                except (json.JSONDecodeError, IOError):
                    existing_logs = []
            
            # Add new entry
            existing_logs.append(log_entry.model_dump())
            
            # Save back to file
            with open(file_path, 'w') as f:
                json.dump(existing_logs, f, indent=2, default=str)
            
            logger.info(f"Saved audit log for task {log_entry.task_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to save audit log: {e}")
            return False
    
    def get_audit_logs(self, task_id: str) -> List[AuditLogEntry]:
        """Retrieve all audit logs for a specific task"""
        try:
            file_path = self._get_audit_file_path(task_id)
            
            if not file_path.exists():
                return []
            
            with open(file_path, 'r') as f:
                logs_data = json.load(f)
            
            return [AuditLogEntry(**log) for log in logs_data]
            
        except Exception as e:
            logger.error(f"Failed to retrieve audit logs: {e}")
            return []
    
    def get_all_task_ids(self) -> List[str]:
        """Get all task IDs that have audit logs"""
        try:
            task_ids = []
            for file_path in self.audit_dir.glob("*.json"):
                task_ids.append(file_path.stem)
            return task_ids
        except Exception as e:
            logger.error(f"Failed to get task IDs: {e}")
            return []
    
    def delete_audit_logs(self, task_id: str) -> bool:
        """Delete audit logs for a specific task"""
        try:
            file_path = self._get_audit_file_path(task_id)
            if file_path.exists():
                file_path.unlink()
                logger.info(f"Deleted audit logs for task {task_id}")
                return True
            return False
        except Exception as e:
            logger.error(f"Failed to delete audit logs: {e}")
            return False
    
    def get_audit_summary(self, task_id: str) -> dict:
        """Get a summary of audit logs for a task"""
        logs = self.get_audit_logs(task_id)
        
        if not logs:
            return {
                "task_id": task_id,
                "total_events": 0,
                "status": "not_found"
            }
        
        # Calculate summary statistics
        total_events = len(logs)
        event_types = {}
        status_counts = {}
        
        for log in logs:
            event_types[log.event_type] = event_types.get(log.event_type, 0) + 1
            status_counts[log.status] = status_counts.get(log.status, 0) + 1
        
        # Determine overall status
        if "error" in status_counts:
            overall_status = "error"
        elif "cancelled" in status_counts:
            overall_status = "cancelled"
        elif "completed" in status_counts:
            overall_status = "completed"
        else:
            overall_status = "in_progress"
        
        return {
            "task_id": task_id,
            "total_events": total_events,
            "overall_status": overall_status,
            "event_types": event_types,
            "status_counts": status_counts,
            "first_event": logs[0].timestamp.isoformat() if logs else None,
            "last_event": logs[-1].timestamp.isoformat() if logs else None,
        }