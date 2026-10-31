export function checkSourceBoundaries(
  relativePath: string,
  source: string,
): string[];

export function checkRepositoryBoundaries(
  rootDirectory: string,
): Promise<string[]>;
