# Worked Example: Oh, Pretty Woman to the January Showcase

Status: Draft, October 23, 2026

A real scenario for testing the app against: one showcase song, one fixed date, 13 weeks, and a voice that has to be built up rather than just rehearsed. It shows what v1 already does, where v1 runs out, and which v2 features this song actually needs. Song materials live in MyOps at `songs/covers/oh-pretty-woman-roy-orbison/`.

## The scenario

| | |
| --- | --- |
| Song | Oh, Pretty Woman (Roy Orbison), reference: *A Black and White Night* live |
| Goal | Vocal showcase, late January 2027 |
| Key | A original; testing A, Ab, and G. Lock by Nov 8 |
| Range | Roughly E3 to F#4 in A |
| Hard parts | Repeated sustained belts near F#4; short phrases with little air; the growl and "Mercy" character beats; the emotional turn before the ending |
| Other checkpoints | Arrangement and backing track locked by Dec 20 |

The 13 weeks run in phases:

| Weeks | Dates | Phase | What the song block should do |
| --- | --- | --- | --- |
| 1-2 | Oct 26 - Nov 8 | Absorb and key | Listen, speak in rhythm, test keys |
| 3-5 | Nov 9 - Nov 29 | Build the top | Isolate the high phrases, half volume up |
| 6-8 | Nov 30 - Dec 20 | Character and story | Growl, "Mercy," the turn; first full takes |
| 9-10 | Dec 21 - Jan 3 | Holiday maintenance | Two or three full runs a week |
| 11-12 | Jan 4 - Jan 17 | Performance mode | Full runs standing, no stopping |
| 13 | Jan 18 - show | Taper | Short runs, nothing new, rest before |

## What v1 does today

Flag the song as a showcase song and it leads the song half of every session.

An illustrative 30-minute day (5 days a week), assuming BFS 125 and 150 are marked solid:

| Half | Item | Min | Why the planner picked it |
| --- | --- | --- | --- |
| Warmups | BFS to 175 | 4 | Current ladder rung, ladders first |
| Warmups | Octave jumps | 4 | Least recently practiced |
| Warmups | Waltz of the Flowers | 4 | Next least recent |
| Warmups | Super Mario x Inspector Gadget | 3 | Fills the 15-minute half |
| Songs | **Oh, Pretty Woman** | 6 | Showcase flag sorts first |
| Songs | Good Ol' Boys | 5 | Learning, least recent |

Already useful from day one:

- Showcase songs never get crowded out.
- A take of every pass, so week 1 and week 10 can be compared.
- The rough-voice check-in halves the song block and steps the ladder back. This matters most for this song, because pushing the top phrases on a tired voice is how it gets damaged.
- The pitch screen shows the range for a sitting, which already answers part of the key question.

## Where v1 runs out

Each gap below is something this song needs that the app can't do yet. Together they make the case for the v2 order.

### 1. The app doesn't know there's a date

The showcase flag is on or off. It has no date and no countdown, and it treats Oct 26 and Jan 20 the same way.

**Showcase mode:** a song gets a showcase date. The app shows "13 weeks, 4 days" on Today, works out the current phase, and changes what the song block does:

- **Early phases:** shorter, section-focused passes
- **Performance mode:** full start-to-finish runs, flagged as "stand up, no stopping"
- **Taper:** one short run, voice check-in required

Checkpoints like "lock key" and "lock arrangement" show as dated tasks on the song.

### 2. It can't help pick the key

The pitch screen measures a sitting's range but keeps nothing, and songs carry a key as plain text with no range.

**Key fitting:**
- Store each song's low and high note in the original key.
- Keep a range history (highest and lowest clean held note, per week).
- Show the song's range against that history in A, Ab, and G. For example: "In A your top is F#4; your clean high this month is G4. One semitone of headroom." That's a real answer to the Nov 8 decision.

### 3. It practices whole songs, not the hard parts

Weeks 3-8 are about four specific spots, not the whole song.

**Song sections:** a song can have named sections with a difficulty flag, for example "top phrases," "Mercy and growl," "the turn," and "outro." In build phases, the song block schedules the flagged section, gives it its own take history, and asks "free, pressed, or cracked?" after each take. The session log template in MyOps already tracks this by hand.

### 4. Lessons and practice don't talk to each other

The questions for Nicolette sit in MyOps `notes.md`. The 10/16 lesson transcript sits in MyOps `meetings/`. Neither reaches the app.

**Pre-lesson brief:** the day before a lesson, the app puts together what was practiced, which sections are still "pressed," and the open questions. **Lesson capture** turns what she says back into warmups, section notes, or a key decision.

## Proposed build order (driven by this song)

1. **Showcase mode.** This is the cheapest and highest value: a `showcaseDate` on Song, a phase calculation in the planner (pure Swift, testable), and a countdown on Today. It must be live by the Nov 9 phase change to matter.
2. **Range history and key fitting.** This extends the existing pitch tracker. Ideally it's done by Nov 8 for the key decision. If not, the decision gets made by ear with Nicolette, and the feature still pays off for the next song.
3. **Song sections.** This model change lands sections, section takes, and the free/pressed/cracked rating. It's needed by the Nov 9 "build the top" phase.
4. **Pre-lesson brief.** It reads from the session logs and section ratings, so it comes after sections.

### Data model additions

| Entity | New fields |
| --- | --- |
| Song | showcaseDate, lowNote, highNote (original key), originalKey |
| Section (new) | song, title, difficultyFlag, order, lastPracticed |
| Take | sectionID (optional), rating (free, pressed, cracked) |
| RangeReading (new) | date, lowNote, highNote |
| Checkpoint (new) | song, title, dueDate, done |

### Planner rule sketch (showcase mode)

- `phase(for: date, showcase: Date) -> ShowcasePhase` from weeks remaining
- **Build phases:** the song item becomes its hardest unresolved section (most recent rating "pressed" or "cracked")
- **Performance phase:** the song item is a full run; minutes set to song length times two
- **Taper:** the song item is one full run, and voice condition 1 or 2 skips it entirely
- Tests: phase boundaries, section selection, taper skip on a rough voice

## Success test for the example

On the showcase date, looking back:

- **Key:** locked by Nov 8 with range data behind the decision.
- **Practice:** every week hit its practice-day target, or the misses are visible.
- **Top phrases:** each one has a "free" take by the end of December.
- **Comparison:** a week 1 take and a final-week take sit side by side.
