// Replaces text in one data file of an atlas draft, as Claude Code's Edit tool does, for plan mode:
// there Edit writes the plan file alone, and the plan map writes its draft through this script.
//
//   bun edit-draft.ts <draft folder> <file> < blocks
//
// stdin holds one block or more, each old text found exactly once in the file, applied in order:
//
//   <<<<<<< OLD
//   the text to replace
//   =======
//   the text that replaces it
//   >>>>>>> NEW
import { existsSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { basename, dirname, join, relative, sep } from "node:path";

const OLD_MARKER = "<<<<<<< OLD";
const MIDDLE_MARKER = "=======";
const NEW_MARKER = ">>>>>>> NEW";

type Replacement = { readonly oldText: string; readonly newText: string };

/** The draft folder's real path, once it is drafts/<name>/ holding a map.ts. */
function resolveDraftFolder(draftArgument: string): string {
  if (!existsSync(draftArgument)) {
    throw new Error(`no folder ${draftArgument}`);
  }

  const draftFolder = realpathSync(draftArgument);
  const draftsFolderName = basename(dirname(draftFolder));

  if (draftsFolderName !== "drafts" || !existsSync(join(draftFolder, "map.ts"))) {
    throw new Error(`${draftFolder} is no atlas draft (drafts/<name>/map.ts)`);
  }

  return draftFolder;
}

/** The data file's real path, once it is a .ts file of the draft other than atlas.d.ts. */
function resolveDataFile(draftFolder: string, fileArgument: string): string {
  const candidatePath = join(draftFolder, fileArgument);

  if (!existsSync(candidatePath)) {
    throw new Error(`no file ${fileArgument} in ${draftFolder}`);
  }

  const dataFile = realpathSync(candidatePath);
  const pathInDraft = relative(draftFolder, dataFile);

  if (pathInDraft.startsWith("..") || pathInDraft.startsWith(sep)) {
    throw new Error(`${fileArgument} lies outside the draft ${draftFolder}`);
  }

  if (!pathInDraft.endsWith(".ts") || pathInDraft === "atlas.d.ts") {
    throw new Error(`${pathInDraft}: only the draft's data files (.ts, not atlas.d.ts) are edited`);
  }

  return dataFile;
}

/** The replacements stdin holds, in order. */
function parseReplacements(blocksText: string): Replacement[] {
  const lines = blocksText.split("\n");
  const replacements: Replacement[] = [];
  let lineIndex = 0;

  while (lineIndex < lines.length) {
    const line = lines[lineIndex];

    // Lines between blocks are blank or ignored.
    if (line !== OLD_MARKER) {
      lineIndex += 1;
      continue;
    }

    const middleIndex = lines.indexOf(MIDDLE_MARKER, lineIndex + 1);
    const newIndex = lines.indexOf(NEW_MARKER, middleIndex + 1);

    if (middleIndex === -1 || newIndex === -1) {
      throw new Error(`the block starting at line ${lineIndex + 1} has no ${MIDDLE_MARKER} or ${NEW_MARKER}`);
    }

    const oldText = lines.slice(lineIndex + 1, middleIndex).join("\n");
    const newText = lines.slice(middleIndex + 1, newIndex).join("\n");

    if (oldText === "") {
      throw new Error(`the block starting at line ${lineIndex + 1} has an empty old text`);
    }

    replacements.push({ oldText, newText });
    lineIndex = newIndex + 1;
  }

  if (replacements.length === 0) {
    throw new Error(`stdin holds no ${OLD_MARKER} block`);
  }

  return replacements;
}

/** The file's text with every replacement applied, each old text found exactly once. */
function applyReplacements(fileText: string, replacements: readonly Replacement[]): string {
  let editedText = fileText;

  for (const [blockIndex, replacement] of replacements.entries()) {
    const firstIndex = editedText.indexOf(replacement.oldText);
    const lastIndex = editedText.lastIndexOf(replacement.oldText);

    if (firstIndex === -1) {
      throw new Error(`block ${blockIndex + 1}: old text not found`);
    }

    if (firstIndex !== lastIndex) {
      throw new Error(`block ${blockIndex + 1}: old text found more than once, add context to it`);
    }

    const textBefore = editedText.slice(0, firstIndex);
    const textAfter = editedText.slice(firstIndex + replacement.oldText.length);
    editedText = `${textBefore}${replacement.newText}${textAfter}`;
  }

  return editedText;
}

const [draftArgument, fileArgument, ...extraArguments] = process.argv.slice(2);

if (draftArgument === undefined || fileArgument === undefined || extraArguments.length > 0) {
  console.error("usage: atlas-plan.sh edit <draft folder> <file> < blocks");
  process.exit(64);
}

try {
  // Check the target, then read the blocks.
  const draftFolder = resolveDraftFolder(draftArgument);
  const dataFile = resolveDataFile(draftFolder, fileArgument);
  const blocksText = await Bun.stdin.text();
  const replacements = parseReplacements(blocksText);

  // Apply every block, then write the file whole: a failing block leaves it unchanged.
  const fileText = readFileSync(dataFile, "utf8");
  const editedText = applyReplacements(fileText, replacements);
  const temporaryFile = `${dataFile}.atlas-plan-edit`;
  writeFileSync(temporaryFile, editedText);
  renameSync(temporaryFile, dataFile);

  console.log(`${relative(draftFolder, dataFile)}: ${replacements.length} block(s) applied`);
} catch (error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(`atlas-plan edit: ${message}; the file is unchanged`);
  process.exit(1);
}
