import { Routes, Route, Navigate } from 'react-router-dom';
import { Layout } from './components/Layout';
import Dashboard from './routes/Dashboard';
import BriefView from './routes/BriefView';
import PendingQueueView from './routes/PendingQueueView';
import AgentsControlPanel from './routes/AgentsControlPanel';
import SignalsView from './routes/SignalsView';
import ResurfacerView from './routes/ResurfacerView';
import FeedbackRefinementView from './routes/FeedbackRefinementView';
import DiagnosticsPanel from './routes/DiagnosticsPanel';

export default function App() {
  return (
    <Routes>
      <Route element={<Layout />}>
        <Route index element={<Dashboard />} />
        <Route path="brief" element={<BriefView />} />
        <Route path="pending" element={<PendingQueueView />} />
        <Route path="agents" element={<AgentsControlPanel />} />
        <Route path="signals" element={<Navigate to="/signals/commercial" replace />} />
        <Route path="signals/:side" element={<SignalsView />} />
        <Route path="resurfacer" element={<ResurfacerView />} />
        <Route path="feedback" element={<FeedbackRefinementView />} />
        <Route path="diagnostics" element={<DiagnosticsPanel />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Route>
    </Routes>
  );
}
