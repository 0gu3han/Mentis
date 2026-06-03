// src/NoteEditor.jsx  —  inline note-creation/editing panel
import React, { useEffect, useRef } from 'react'

/**
 * Props
 *  anchorLabel  – shown in the header
 *  title        – controlled value
 *  body         – controlled value
 *  saving       – bool, disables controls while request is in flight
 *  onTitleChange / onBodyChange
 *  onSave / onCancel
 */
export default function NoteEditor({
  anchorLabel,
  title,
  body,
  saving,
  onTitleChange,
  onBodyChange,
  onSave,
  onCancel,
}) {
  const titleRef = useRef(null)

  // Auto-focus the title field when the editor opens
  useEffect(() => { titleRef.current?.focus() }, [])

  function handleKeyDown(e) {
    if (e.key === 'Escape') onCancel()
    // Ctrl/Cmd+Enter submits from either field
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') onSave()
  }

  return (
    <div className="note-editor" onKeyDown={handleKeyDown}>
      <div className="note-editor-header">
        <span>📝 Note for <em>{anchorLabel}</em></span>
        <button className="note-editor-close" onClick={onCancel} title="Cancel (Esc)">✕</button>
      </div>

      <div className="note-editor-field">
        <label>Title</label>
        <input
          ref={titleRef}
          value={title}
          onChange={(e) => onTitleChange(e.target.value)}
          placeholder="e.g. Mitochondria function"
          disabled={saving}
        />
      </div>

      <div className="note-editor-field">
        <label>Note / mnemonic</label>
        <textarea
          value={body}
          onChange={(e) => onBodyChange(e.target.value)}
          placeholder="Write your mnemonic, summary, or memory cue here…"
          rows={5}
          disabled={saving}
        />
      </div>

      <div className="note-editor-actions">
        <span className="note-editor-hint">Ctrl+Enter to save</span>
        <button className="note-editor-cancel" onClick={onCancel} disabled={saving}>
          Cancel
        </button>
        <button
          className="note-editor-save"
          onClick={onSave}
          disabled={saving || !title.trim()}
        >
          {saving ? 'Saving…' : '✓ Save Note'}
        </button>
      </div>
    </div>
  )
}
