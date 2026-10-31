import { z } from "zod";

export type FormFieldErrors = Readonly<Record<string, readonly string[]>>;

export type SchemaFormResult<T> =
  | { success: true; data: T; fieldErrors: Record<string, never> }
  | { success: false; data?: never; fieldErrors: FormFieldErrors };

function formDataRecord(
  formData: FormData,
): Record<string, FormDataEntryValue | FormDataEntryValue[]> {
  const result: Record<string, FormDataEntryValue | FormDataEntryValue[]> = {};

  for (const [key, value] of formData.entries()) {
    const existing = result[key];
    if (existing === undefined) result[key] = value;
    else if (Array.isArray(existing)) existing.push(value);
    else result[key] = [existing, value];
  }

  return result;
}

function issuePath(issue: z.core.$ZodIssue): string {
  return issue.path.length === 0 ? "_form" : issue.path.join(".");
}

export function zodFieldErrors(error: z.ZodError): FormFieldErrors {
  const errors: Record<string, string[]> = {};
  for (const issue of error.issues) {
    const path = issuePath(issue);
    (errors[path] ??= []).push(issue.message);
  }
  return errors;
}

export function parseSchemaForm<T>(
  schema: z.ZodType<T>,
  formData: FormData,
): SchemaFormResult<T> {
  const parsed = schema.safeParse(formDataRecord(formData));
  return parsed.success
    ? { success: true, data: parsed.data, fieldErrors: {} }
    : { success: false, fieldErrors: zodFieldErrors(parsed.error) };
}
