import QueueView from './QueueView';

// Pitch Deck Edits approval queue. Slide-by-slide before/after edits proposed
// by pitch-deck-updater; Apply appends each approved edit to the operator's
// Desktop hand-off doc (the deck itself is never edited programmatically).
export default function PitchDeckQueueView() {
  return (
    <QueueView
      queue="pitch-deck"
      title="Pitch Deck Edits"
      emptyText="No pending pitch-deck edits. The investor-analyzer weekly run chains pitch-deck-updater, which populates this list."
    />
  );
}
