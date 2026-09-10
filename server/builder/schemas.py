from __future__ import annotations

from enum import Enum
from typing import List, Optional

from pydantic import BaseModel, Field


class BuilderJobStatus(str, Enum):
    QUEUED = "queued"
    ANALYZING = "analyzing"
    PLANNING = "planning"
    GENERATING = "generating"
    VALIDATING = "validating"
    PREVIEW_READY = "preview_ready"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"


class BuilderGenerateRequest(BaseModel):
    """Create a new Builder job. Either a free-form prompt or a source URL.

    `mode` mirrors the analyse-first workflow: ``prompt`` builds purely from an
    idea, ``url`` analyses a live website (Firecrawl) and then builds an
    independent implementation of it.
    """

    prompt: str = Field(min_length=8, max_length=1000)
    url: Optional[str] = None
    mode: str = Field(default="prompt", pattern="^(prompt|url)$")


class BuilderGenerateResponse(BaseModel):
    job_id: str
    status: str = BuilderJobStatus.QUEUED.value


class BuilderEvent(BaseModel):
    type: str = "progress"
    status: str
    step_index: int
    progress: int
    message: str
    time: str


class BuilderProjectMeta(BaseModel):
    """Re-serializable project record stored at
    generated_projects/<project_id>/metadata.json. NEVER contains secrets."""

    project_id: str
    title: str
    prompt: str
    source_url: Optional[str] = None
    created_at: str
    updated_at: str
    status: str = BuilderJobStatus.COMPLETED.value
    files: List[str] = Field(default_factory=list)


class BuilderJobView(BaseModel):
    job_id: str
    status: str
    mode: str
    prompt: str
    url: Optional[str] = None
    step_index: int = 0
    progress: int = 0
    message: str = ""
    error: Optional[str] = None
    cancelled: bool = False
    project_id: Optional[str] = None
    events: List[BuilderEvent] = Field(default_factory=list)
    project: Optional[BuilderProjectMeta] = None


class BuilderCancelResponse(BaseModel):
    job_id: str
    cancelled: bool


class BuilderFileResponse(BaseModel):
    project_id: str
    path: str
    content: str