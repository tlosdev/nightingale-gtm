import { useMemo } from 'react';
import { marked } from 'marked';
import DOMPurify from 'dompurify';

interface Props {
  markdown: string;
  className?: string;
}

// Renders agent markdown with strict sanitization. The agents themselves
// guarantee paraphrased content (no verbatim emails), but defense-in-depth:
// DOMPurify strips any script/iframe/object that could appear if an agent
// ever drifts.
//
// marked v14 ships its own types and a string-returning parse() when
// async:false is explicit. We pin the option here so the cast is sound even
// if any future option default changes (marked has changed its async default
// in past minor releases).
marked.setOptions({
  gfm: true,
  breaks: false,
  async: false,
});

export function MarkdownRenderer({ markdown, className }: Props) {
  const html = useMemo(() => {
    const dirty = marked.parse(markdown ?? '', { async: false }) as string;
    const clean = DOMPurify.sanitize(dirty, {
      USE_PROFILES: { html: true },
      ALLOWED_TAGS: [
        'a', 'b', 'blockquote', 'br', 'code', 'em', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
        'hr', 'i', 'img', 'li', 'ol', 'p', 'pre', 'small', 'span', 'strong', 'sub', 'sup',
        'table', 'tbody', 'td', 'tfoot', 'th', 'thead', 'tr', 'ul', 'del', 'ins',
      ],
      ALLOWED_ATTR: ['href', 'title', 'alt', 'src', 'class', 'colspan', 'rowspan'],
      // https:// only. We previously allowed http: and mailto: — http: was
      // open to mixed-content injection on a localhost UI and mailto: in an
      // <img src> is nonsensical. Operator-facing markdown rarely needs
      // either; if a future need for mailto: links arises, add it back with
      // a per-tag config (DOMPurify doesn't make per-attr regex easy).
      ALLOWED_URI_REGEXP: /^https:/i,
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
