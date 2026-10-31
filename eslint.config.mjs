import nextVitals from "eslint-config-next/core-web-vitals";
import nextTypeScript from "eslint-config-next/typescript";

const eslintConfig = [
  ...nextVitals,
  ...nextTypeScript,
  {
    ignores: [".next/**", "coverage/**", "node_modules/**", "next-env.d.ts"],
  },
  {
    files: ["src/contracts/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: [
                "next",
                "next/**",
                "openai",
                "@supabase/**",
                "@/lib/**",
                "@/modules/**",
              ],
              message:
                "Contracts must remain framework- and infrastructure-independent.",
            },
          ],
        },
      ],
    },
  },
  {
    files: ["src/modules/gameplay/**/*.{ts,tsx}"],
    rules: {
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["openai", "@/lib/openai/**"],
              message: "Gameplay cannot call the model provider.",
            },
          ],
        },
      ],
    },
  },
];

export default eslintConfig;
