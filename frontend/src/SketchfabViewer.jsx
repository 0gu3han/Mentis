// src/SketchfabViewer.jsx
import React, { useEffect, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { listAnchors, createAnchor, createObject, deleteAnchor } from './api'
import NoteEditor from './NoteEditor'

const SKETCHFAB_API_SRC = 'https://static.sketchfab.com/api/sketchfab-viewer-1.12.1.js'

function loadSketchfabScript() {
  return new Promise((resolve, reject) => {
    if (window.Sketchfab) { resolve(); return }
    const existing = document.getElementById('sketchfab-api')
    if (existing) {
      existing.addEventListener('load', resolve)
      existing.addEventListener('error', reject)
      return
    }
    const s = document.createElement('script')
    s.id = 'sketchfab-api'
    s.src = SKETCHFAB_API_SRC
    s.onload = resolve
    s.onerror = reject
    document.head.appendChild(s)
  })
}

export default function SketchfabViewer({ modelId, roomName }) {
  const iframeRef = useRef()
  const apiRef = useRef(null)
  const clickHandlerRef = useRef(null)
  const labelRef = useRef('Note')

  const [label, setLabel] = useState('Note')
  const [anchors, setAnchors] = useState([])
  const [noteEditor, setNoteEditor] = useState(null)
  const [placingAnchor, setPlacingAnchor] = useState(false)
  const [apiReady, setApiReady] = useState(false)
  const [status, setStatus] = useState('Loading viewer…')

  // Synthetic room ID for backend storage
  const roomId = `sketchfab-${modelId}`

  // Keep labelRef in sync so the closure always reads the latest value
  useEffect(() => { labelRef.current = label }, [label])

  // ── Initialize Sketchfab Viewer API ───────────────────────────────────────
  useEffect(() => {
    if (!iframeRef.current) return
    let cancelled = false
    setApiReady(false)
    setPlacingAnchor(false)
    setStatus('Loading Sketchfab API…')

    loadSketchfabScript()
      .then(() => {
        if (cancelled || !iframeRef.current) return
        setStatus('Initializing viewer…')
        const client = new window.Sketchfab(iframeRef.current)
        client.init(modelId, {
          success(api) {
            if (cancelled) return
            apiRef.current = api
            api.start()
            api.addEventListener('viewerready', () => {
              if (cancelled) return
              setApiReady(true)
              setStatus('Ready — click "Place Anchor" then click on the model')
            })
          },
          error() {
            if (!cancelled) setStatus('⚠ Failed to load model')
          },
          autostart: 1,
          preload: 1,
          ui_annotations: 1,
          ui_controls: 1,
          ui_infos: 0,
          ui_watermark_link: 0,
        })
      })
      .catch(() => {
        if (!cancelled) setStatus('⚠ Failed to load Sketchfab API')
      })

    return () => {
      cancelled = true
      if (apiRef.current && clickHandlerRef.current) {
        try { apiRef.current.removeEventListener('click', clickHandlerRef.current) } catch (_) {}
        clickHandlerRef.current = null
      }
      apiRef.current = null
      setApiReady(false)
    }
  }, [modelId])

  // ── Toggle click listener for anchor placement ────────────────────────────
  useEffect(() => {
    if (!apiReady || !apiRef.current) return

    if (placingAnchor) {
      const handler = (info) => {
        if (!info || !info.position3D) return
        const [px, py, pz] = info.position3D
        const [nx, ny, nz] = info.normal3D || [0, 1, 0]
        const currentLabel = labelRef.current

        apiRef.current.getCameraLookAt((err, camera) => {
          if (err) { console.error('getCameraLookAt error:', err); return }
          const eye = camera.position
          const target = camera.target

          // Create a visual annotation inside Sketchfab
          apiRef.current.createAnnotationFromWorldPosition(
            [px, py, pz],
            eye,
            target,
            currentLabel,
            '',
            (err2) => { if (err2) console.error('Annotation error:', err2) }
          )

          // Persist to backend
          createAnchor({
            room_id: roomId,
            label: currentLabel,
            pos: [px, py, pz],
            normal: [nx, ny, nz],
          })
            .then((res) => { if (res.anchor_id) refreshAnchors() })
            .catch(console.error)
        })

        // One-shot — exit placing mode
        setPlacingAnchor(false)
      }

      clickHandlerRef.current = handler
      apiRef.current.addEventListener('click', handler)
    } else {
      if (clickHandlerRef.current && apiRef.current) {
        try { apiRef.current.removeEventListener('click', clickHandlerRef.current) } catch (_) {}
        clickHandlerRef.current = null
      }
    }

    return () => {
      if (apiRef.current && clickHandlerRef.current) {
        try { apiRef.current.removeEventListener('click', clickHandlerRef.current) } catch (_) {}
        clickHandlerRef.current = null
      }
    }
  }, [placingAnchor, apiReady])

  // ── Backend anchor helpers ────────────────────────────────────────────────
  async function refreshAnchors() {
    try {
      const data = await listAnchors(roomId)
      setAnchors(data.anchors || [])
    } catch (e) {
      console.error('refreshAnchors:', e)
    }
  }

  useEffect(() => { refreshAnchors() }, [roomId])

  function openNoteEditor(anchor) {
    setNoteEditor({ anchorId: anchor.id, label: anchor.label || `Anchor ${anchor.id}`, title: '', body: '', saving: false })
  }

  async function saveNote() {
    if (!noteEditor || !noteEditor.title.trim()) return
    setNoteEditor((n) => ({ ...n, saving: true }))
    try {
      const res = await createObject({ anchor_id: noteEditor.anchorId, title: noteEditor.title, body: noteEditor.body, kind: 'text' })
      if (res.object_id) {
        await refreshAnchors()
        setNoteEditor(null)
      }
    } catch (err) {
      setNoteEditor((n) => ({ ...n, saving: false }))
      console.error('saveNote:', err)
    }
  }

  async function removeAnchor(e, anchor) {
    e.stopPropagation()
    if (!window.confirm(`Delete anchor "${anchor.label || `Anchor ${anchor.id}`}" and all its notes?`)) return
    try {
      // Also remove the Sketchfab native annotation if API is ready
      if (apiRef.current) {
        apiRef.current.getAnnotationList((err, list) => {
          if (err || !list) return
          list.forEach((ann, idx) => {
            if (ann.name === anchor.label) {
              apiRef.current.removeAnnotation(idx, () => {})
            }
          })
        })
      }
      await deleteAnchor(anchor.id)
      if (noteEditor?.anchorId === anchor.id) setNoteEditor(null)
      await refreshAnchors()
    } catch (err) { console.error('removeAnchor:', err) }
  }

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <div className="room-viewer">
      <div className="toolbar">
        <Link to="/" className="back-btn">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="15 18 9 12 15 6"/>
          </svg>
          Rooms
        </Link>
        <span className="toolbar-room-name">{roomName || modelId}</span>
      </div>

      <div className="stage">
        <iframe
          ref={iframeRef}
          title={roomName || modelId}
          frameBorder="0"
          allowFullScreen
          mozallowfullscreen="true"
          webkitallowfullscreen="true"
          allow="autoplay; fullscreen; xr-spatial-tracking"
          style={{ width: '100%', height: '100%', border: 'none', display: 'block' }}
        />
        {placingAnchor && (
          <div className="placement-hint">
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/>
            </svg>
            Click any surface to place anchor
          </div>
        )}
      </div>

      <div className="sidebar">
        <div className="sidebar-header">
          <span className="sidebar-title">Anchors</span>
          {anchors.length > 0 && <span className="sidebar-count">{anchors.length}</span>}
        </div>

        <div className="sidebar-place-anchor">
          <button
            className={`place-anchor-btn${placingAnchor ? ' active' : ''}`}
            onClick={() => setPlacingAnchor((p) => !p)}
            disabled={!apiReady}
          >
            <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/>
              <circle cx="12" cy="9" r="2.5"/>
            </svg>
            {placingAnchor ? 'Click a surface…' : 'Place Anchor'}
          </button>
          {placingAnchor && (
            <input
              className="toolbar-label-input sidebar-label-input"
              value={label}
              onChange={(e) => setLabel(e.target.value)}
              placeholder="Label (optional)"
              autoFocus
            />
          )}
        </div>

        {noteEditor ? (
          <NoteEditor
            anchorLabel={noteEditor.label}
            title={noteEditor.title}
            body={noteEditor.body}
            saving={noteEditor.saving}
            onTitleChange={(v) => setNoteEditor((n) => ({ ...n, title: v }))}
            onBodyChange={(v)  => setNoteEditor((n) => ({ ...n, body:  v }))}
            onSave={saveNote}
            onCancel={() => setNoteEditor(null)}
          />
        ) : (
          <ul>
            {anchors.length === 0 && (
              <li className="anchor-empty">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7z"/>
                  <circle cx="12" cy="9" r="2.5"/>
                </svg>
                <span>No anchors yet</span>
                <span className="anchor-empty-sub">Place an anchor then click on the model</span>
              </li>
            )}
            {anchors.map((a, idx) => (
              <li key={a.id} className="anchor-item">
                <div className="anchor-header">
                  <span className="anchor-num">{idx + 1}</span>
                  <strong>{a.label || `Anchor ${a.id}`}</strong>
                  <button className="delete-btn" title="Delete anchor" onClick={(e) => removeAnchor(e, a)}>
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round">
                      <line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/>
                    </svg>
                  </button>
                </div>
                {a.objects && a.objects.length > 0 && (
                  <div className="anchor-objects">
                    {a.objects.map((obj) => (
                      <div key={obj.id} className="object-item">
                        <strong>{obj.title}</strong>
                        {obj.body && <div className="object-body">{obj.body}</div>}
                      </div>
                    ))}
                  </div>
                )}
                <button className="add-note-btn" onClick={() => openNoteEditor(a)}>
                  <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                    <line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/>
                  </svg>
                  Add note
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>
    </div>
  )
}
