import type {
  ButtonHTMLAttributes,
  DialogHTMLAttributes,
  HTMLAttributes,
  InputHTMLAttributes,
  ReactNode,
  TextareaHTMLAttributes,
} from "react";

import { cn } from "@/lib/ui/cn";

type Tone = "neutral" | "orange" | "violet" | "success" | "warning" | "danger";

const toneClasses: Record<Tone, string> = {
  neutral: "border-white/15 bg-white/5 text-stone-200",
  orange: "border-orange-400/30 bg-orange-400/10 text-orange-200",
  violet: "border-violet-400/30 bg-violet-400/10 text-violet-200",
  success: "border-emerald-400/30 bg-emerald-400/10 text-emerald-100",
  warning: "border-amber-300/30 bg-amber-300/10 text-amber-100",
  danger: "border-rose-400/30 bg-rose-400/10 text-rose-100",
};

export function Button({
  className,
  variant = "primary",
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "secondary" | "ghost" | "danger";
}) {
  const variants = {
    primary:
      "bg-orange-400 text-stone-950 hover:bg-orange-300 active:bg-orange-500",
    secondary:
      "border border-white/20 bg-white/8 text-white hover:bg-white/14 active:bg-white/5",
    ghost: "text-stone-200 hover:bg-white/8 active:bg-white/5",
    danger:
      "border border-rose-300/30 bg-rose-400/15 text-rose-100 hover:bg-rose-400/25",
  } as const;

  return (
    <button
      className={cn(
        "inline-flex min-h-11 items-center justify-center rounded-xl px-4 py-2.5 text-sm font-extrabold transition disabled:cursor-not-allowed disabled:opacity-45",
        variants[variant],
        className,
      )}
      {...props}
    />
  );
}

export function Card({
  className,
  elevated = false,
  ...props
}: HTMLAttributes<HTMLDivElement> & { elevated?: boolean }) {
  return (
    <div
      className={cn(
        "rounded-2xl border border-white/10 bg-[var(--surface)] p-5",
        elevated && "bg-[var(--surface-raised)] shadow-xl shadow-black/25",
        className,
      )}
      {...props}
    />
  );
}

export function StatusBadge({
  children,
  tone = "neutral",
  className,
}: {
  children: ReactNode;
  tone?: Tone;
  className?: string;
}) {
  return (
    <span
      className={cn(
        "inline-flex min-h-7 items-center rounded-full border px-2.5 py-1 text-xs font-bold",
        toneClasses[tone],
        className,
      )}
    >
      {children}
    </span>
  );
}

export function FormField({
  id,
  label,
  hint,
  error,
  children,
}: {
  id: string;
  label: string;
  hint?: string;
  error?: string;
  children: ReactNode;
}) {
  const descriptionId = hint || error ? `${id}-description` : undefined;

  return (
    <div className="grid gap-2">
      <label htmlFor={id} className="text-sm font-bold text-stone-100">
        {label}
      </label>
      {children}
      {hint || error ? (
        <p
          id={descriptionId}
          className={cn(
            "text-sm leading-5",
            error ? "text-rose-200" : "text-stone-400",
          )}
        >
          {error ?? hint}
        </p>
      ) : null}
    </div>
  );
}

export function Input({
  className,
  ...props
}: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "min-h-11 w-full rounded-xl border border-white/15 bg-black/20 px-3.5 py-2.5 text-base text-white placeholder:text-stone-500 hover:border-white/25 disabled:cursor-not-allowed disabled:opacity-55",
        className,
      )}
      {...props}
    />
  );
}

export function Textarea({
  className,
  ...props
}: TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return (
    <textarea
      className={cn(
        "min-h-32 w-full resize-y rounded-xl border border-white/15 bg-black/20 px-3.5 py-3 text-base leading-6 text-white placeholder:text-stone-500 hover:border-white/25 disabled:cursor-not-allowed disabled:opacity-55",
        className,
      )}
      {...props}
    />
  );
}

export function Alert({
  title,
  children,
  tone = "neutral",
  className,
}: {
  title: string;
  children: ReactNode;
  tone?: Tone;
  className?: string;
}) {
  return (
    <section
      className={cn("rounded-2xl border p-4", toneClasses[tone], className)}
      aria-label={title}
    >
      <h3 className="font-extrabold">{title}</h3>
      <div className="mt-1 text-sm leading-6 opacity-90">{children}</div>
    </section>
  );
}

export function Dialog({
  open,
  title,
  description,
  children,
  actions,
  className,
  ...props
}: DialogHTMLAttributes<HTMLDialogElement> & {
  title: string;
  description?: string;
  actions?: ReactNode;
}) {
  return (
    <dialog
      open={open}
      aria-labelledby="dialog-title"
      aria-describedby={description ? "dialog-description" : undefined}
      className={cn(
        "m-auto w-[min(32rem,calc(100%-2rem))] rounded-3xl border border-white/15 bg-[var(--surface-raised)] p-0 text-[var(--ink)] shadow-2xl backdrop:bg-black/75",
        className,
      )}
      {...props}
    >
      <div className="p-5 sm:p-6">
        <h2 id="dialog-title" className="text-xl font-black">
          {title}
        </h2>
        {description ? (
          <p
            id="dialog-description"
            className="mt-2 text-sm leading-6 text-stone-300"
          >
            {description}
          </p>
        ) : null}
        <div className="mt-5">{children}</div>
        {actions ? (
          <div className="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
            {actions}
          </div>
        ) : null}
      </div>
    </dialog>
  );
}

export function Tabs({
  label,
  tabs,
  activeId,
}: {
  label: string;
  tabs: ReadonlyArray<{
    id: string;
    label: string;
    href: string;
    count?: number;
  }>;
  activeId: string;
}) {
  return (
    <nav aria-label={label} className="overflow-x-auto">
      <div className="flex min-w-max gap-1 rounded-xl border border-white/10 bg-black/20 p-1">
        {tabs.map((tab) => {
          const active = tab.id === activeId;
          return (
            <a
              key={tab.id}
              href={tab.href}
              aria-current={active ? "page" : undefined}
              className={cn(
                "inline-flex min-h-10 items-center gap-2 rounded-lg px-3 py-2 text-sm font-bold",
                active
                  ? "bg-white/12 text-white"
                  : "text-stone-400 hover:bg-white/6 hover:text-white",
              )}
            >
              {tab.label}
              {tab.count === undefined ? null : (
                <span className="rounded-full bg-black/30 px-1.5 text-xs">
                  {tab.count}
                </span>
              )}
            </a>
          );
        })}
      </div>
    </nav>
  );
}

export function PlayerCard({
  name,
  costume,
  status,
  statusTone = "neutral",
  action,
}: {
  name: string;
  costume: string;
  status: string;
  statusTone?: Tone;
  action?: ReactNode;
}) {
  return (
    <Card className="flex min-w-0 items-center gap-3 p-4">
      <span
        aria-hidden="true"
        className="grid size-11 shrink-0 place-items-center rounded-full bg-violet-400/15 text-lg font-black text-violet-200"
      >
        {Array.from(name.trim())[0]?.toLocaleUpperCase() ?? "?"}
      </span>
      <div className="min-w-0 flex-1">
        <h3 className="break-words font-extrabold">{name}</h3>
        <p className="break-words text-sm text-stone-400">{costume}</p>
      </div>
      <div className="flex shrink-0 flex-col items-end gap-2">
        <StatusBadge tone={statusTone}>{status}</StatusBadge>
        {action}
      </div>
    </Card>
  );
}

export function SecretPanel({
  eyebrow = "Private",
  title,
  children,
}: {
  eyebrow?: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="relative overflow-hidden rounded-2xl border border-violet-300/25 bg-violet-400/10 p-5">
      <div
        aria-hidden="true"
        className="absolute -top-12 -right-12 size-32 rounded-full bg-violet-400/10 blur-2xl"
      />
      <p className="text-xs font-black tracking-[0.18em] text-violet-200 uppercase">
        {eyebrow}
      </p>
      <h2 className="mt-2 text-xl font-black">{title}</h2>
      <div className="mt-3 text-sm leading-6 text-stone-200">{children}</div>
    </section>
  );
}

export function EvidenceCard({
  kind,
  title,
  children,
  audience,
}: {
  kind: string;
  title: string;
  children: ReactNode;
  audience: string;
}) {
  return (
    <Card className="border-amber-200/15 bg-amber-200/5">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <StatusBadge tone="warning">{kind}</StatusBadge>
        <span className="text-xs font-bold text-stone-400">{audience}</span>
      </div>
      <h3 className="mt-4 text-lg font-black">{title}</h3>
      <div className="mt-2 text-sm leading-6 text-stone-300">{children}</div>
    </Card>
  );
}

export function MissionCard({
  status,
  title,
  objective,
  stakes,
  action,
}: {
  status: string;
  title: string;
  objective: string;
  stakes: string;
  action?: ReactNode;
}) {
  return (
    <Card elevated>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <StatusBadge tone="orange">{status}</StatusBadge>
          <h3 className="mt-3 break-words text-lg font-black">{title}</h3>
        </div>
        <span aria-hidden="true" className="text-2xl">
          ◆
        </span>
      </div>
      <p className="mt-3 text-sm leading-6 text-stone-200">{objective}</p>
      <p className="mt-3 border-l-2 border-orange-300/40 pl-3 text-xs leading-5 text-stone-400">
        {stakes}
      </p>
      {action ? <div className="mt-5">{action}</div> : null}
    </Card>
  );
}

export function Timeline({
  items,
}: {
  items: ReadonlyArray<{
    id: string;
    title: string;
    detail?: string;
    current?: boolean;
  }>;
}) {
  return (
    <ol className="grid gap-0">
      {items.map((item, index) => (
        <li key={item.id} className="grid grid-cols-[1.5rem_1fr] gap-3">
          <div className="flex flex-col items-center">
            <span
              className={cn(
                "mt-1 size-3 rounded-full border-2",
                item.current
                  ? "border-orange-200 bg-orange-400"
                  : "border-stone-500 bg-[var(--surface)]",
              )}
            />
            {index === items.length - 1 ? null : (
              <span className="min-h-8 w-px flex-1 bg-white/15" />
            )}
          </div>
          <div className="pb-5">
            <p
              className={cn(
                "font-bold",
                item.current ? "text-white" : "text-stone-300",
              )}
            >
              {item.title}
            </p>
            {item.detail ? (
              <p className="mt-1 text-sm leading-5 text-stone-400">
                {item.detail}
              </p>
            ) : null}
          </div>
        </li>
      ))}
    </ol>
  );
}

export function Toast({
  title,
  children,
  tone = "neutral",
}: {
  title: string;
  children?: ReactNode;
  tone?: Tone;
}) {
  return (
    <div
      role={tone === "danger" ? "alert" : "status"}
      className={cn(
        "rounded-xl border p-4 shadow-xl shadow-black/25",
        toneClasses[tone],
      )}
    >
      <p className="font-extrabold">{title}</p>
      {children ? (
        <div className="mt-1 text-sm leading-5 opacity-90">{children}</div>
      ) : null}
    </div>
  );
}

export function StickyActionBar({ children }: { children: ReactNode }) {
  return (
    <div className="sticky bottom-0 z-20 -mx-4 mt-8 border-t border-white/10 bg-[#0d0b10]/95 p-4 pb-[max(1rem,env(safe-area-inset-bottom))] backdrop-blur sm:mx-0 sm:rounded-t-2xl sm:border-x">
      <div className="mx-auto flex w-full max-w-3xl flex-col gap-2 sm:flex-row sm:justify-end">
        {children}
      </div>
    </div>
  );
}
