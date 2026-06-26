import { useParams, useLocation } from 'react-router-dom'
import SketchfabViewer from './SketchfabViewer'

export default function DemoViewerPage() {
  const { modelId } = useParams()
  const { state } = useLocation()
  const roomName = state?.roomName || 'Demo Room'

  return (
    <div className="viewer-page">
      <SketchfabViewer modelId={modelId} roomName={roomName} />
    </div>
  )
}
