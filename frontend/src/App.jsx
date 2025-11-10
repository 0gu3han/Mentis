import React, { useEffect, useRef, useState } from 'react'
import { login, createRoom, listRooms, roomGlbUrl } from './api'
import RoomViewer from './RoomViewer'

export default function App() {
  const [user, setUser] = useState(null)
  const [loginError, setLoginError] = useState(null)
  const [rooms, setRooms] = useState([])
  const [activeRoom, setActiveRoom] = useState(null)
  const fileRef = useRef()
  const nameRef = useRef()

  useEffect(() => {
    login('demo@mentis.app')
      .then(setUser)
      .catch((err) => {
        console.error('Login failed', err)
        setLoginError(err.message || String(err))
        // optional: show an alert so user notices
        alert(`Login failed: ${err.message || err}`)
      })
  }, [])

  useEffect(() => {
    if (user) listRooms(user.user_id).then((r) => setRooms(r.rooms))
  }, [user])

  async function onUpload() {
    if (!user) {
      if (loginError) {
        alert(`Cannot upload: login failed (${loginError}). Check backend and VITE_API_BASE.`)
      } else {
        alert('Please wait for login to complete')
      }
      return
    }
    const file = fileRef.current.files[0]
    if (!file) {
      alert('Pick a GLB file from Polycam')
      return
    }
    try {
      const result = await createRoom(user.user_id, nameRef.current.value || 'My Room', file)
      if (result.error) {
        alert(`Upload failed: ${result.error}`)
        return
      }
      // Clear the file input
      fileRef.current.value = ''
      nameRef.current.value = ''
      // Refresh rooms list
      const roomsData = await listRooms(user.user_id)
      setRooms(roomsData.rooms)
      alert(`Room "${result.name}" uploaded successfully!`)
    } catch (error) {
      console.error('Upload error:', error)
      alert(`Upload failed: ${error.message}. Make sure the backend is running on ${import.meta.env.VITE_API_BASE || 'http://localhost:8000'}`)
    }
  }

  return (
    <div className="app">
      <header>
        <h1>Mentis – Memory Palace</h1>
      </header>

      <section className="uploader">
        <input ref={nameRef} placeholder="Room name" />
        <input ref={fileRef} type="file" accept=".glb,.gltf,.obj,.usdz" />
        <button onClick={onUpload}>Upload Room</button>
      </section>

      <section className="rooms">
        <ul>
          {rooms.map((r) => (
            <li key={r.id}>
              <button onClick={() => setActiveRoom(r)}>{r.name}</button>
            </li>
          ))}
        </ul>
      </section>

      <section className="viewer">
        {activeRoom ? (
          <RoomViewer
            roomId={activeRoom.id}
            glbUrl={roomGlbUrl(activeRoom.id)}
          />
        ) : (
          <p>Select a room to view</p>
        )}
      </section>
    </div>
  )
}
