// Tiny helpers around marked + dompurify for server-side markdown handling.
// The actual rich rendering happens on the frontend; the server side mostly
// pulls structured signals OUT of agent md files (e.g. extracting tables
// from the daily-brief). When that fails, the route returns the raw md and
// the frontend renders it as best-effort.
import fs from 'node:fs';

/**
 * Read a UTF-8 file, returning null if it doesn't exist. Throws on other I/O
 * errors (e.g. permission denied) so the caller surfaces them.
 */
export function readFileOrNull(path: string): string | null {
  try {
    return fs.readFileSync(path, 'utf8');
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === 'ENOENT') return null;
    throw err;
  }
}

/**
 * Extract the top H1 from a markdown document. Useful for surfacing the
 * date / title without parsing the whole file.
 */
export function extractH1(md: string): string | null {
  const m = md.match(/^#\s+(.+)$/m);
  return m ? m[1].trim() : null;
}

/**
 * Split a markdown doc by H2 headings into a flat object map.
 * Returns { '## Heading text': 'body markdown until next H2', ... }.
 * Used by route parsers to find specific sections without committing to a
 * full AST library. Lossy by design — frontend always gets the raw md too.
 */
export function splitByH2(md: string): Record<string, string> {
  const sections: Record<string, string> = {};
  const lines = md.split(/\r?\n/);
  let currentHeading: string | null = null;
  let currentBody: string[] = [];
  for (const line of lines) {
    const h2 = line.match(/^##\s+(.+)$/);
    if (h2) {
      if (currentHeading !== null) {
        sections[currentHeading] = currentBody.join('\n').trim();
      }
      currentHeading = h2[1].trim();
      currentBody = [];
    } else if (currentHeading !== null) {
      currentBody.push(line);
    }
  }
  if (currentHeading !== null) {
    sections[currentHeading] = currentBody.join('\n').trim();
  }
  return sections;
}

/**
 * Find the date in a daily-brief / signals filename like
 * `daily-brief-2026-05-30.md` → `2026-05-30`. Returns null if no date found.
 */
export function extractDateFromFilename(name: string): string | null {
  const m = name.match(/(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : null;
}
