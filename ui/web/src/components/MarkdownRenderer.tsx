import { useMemo } from 'react';
import { marked } from 'marked';
import DOMPurify from 'isomorphic-dompurify';

interface Props {
  markdown: string;
  className?: string;
}

// Renders agent markdown with strict sanitization. The agents themselves
// guarantee paraphrased content (no verbatim emails), but defense-in-depth:
// dompurify strips any script/iframe/object that could appear if an agent
// ever drifts. marked is configured GFM-on for tables.
marked.setOptions({
  gfm: true,
  breaks: false,
});

export function MarkdownRenderer({ markdown, className }: Props) {
  const html = useMemo(() => {
    const dirty = marked.parse(markdown ?? '') as string;
    const clean = DOMPurify.sanitize(dirty, {
      USE_PROFILES: { html: true },
      ALLOWED_TAGS: [
        'a', 'b', 'blockquote', 'br', 'code', 'em', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'hr', 'i', 'img', 'li', 'ol', 'p', 'pre', 'small', 'span', 'strong', 'sub', 'sup',
        'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul', 'del', 'ins',
      ],
      ALLOWED_ATTR: ['href', 'title', 'alt', 'src', 'class', 'colspan', 'rowspan'],
      ALLOWED_URI_REGEXP: /^(?:https?|mailto):/i,
    });
    return clean;
  }, [markdown]);
  return (
    <div
      className={`md-content ${className ?? ''}`}
      // eslint-disable-next-line react/no-danger
      dangerouslySetInnerHTML={{ __html: html }}
    />
  );
}
