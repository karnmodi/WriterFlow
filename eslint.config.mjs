// @ts-check
import js from "@eslint/js";
import tseslint from "typescript-eslint";

export default tseslint.config(
  {
    ignores: [
      "**/dist/**",
      "**/node_modules/**",
      "website/**",
      "build/**",
      ".build/**",
      "Docs/**",
      "**/migrations/**/*.cjs",
      "eslint.config.mjs",
      "**/vitest.config.ts",
      "scripts/*.mjs"
    ]
  },
  js.configs.recommended,
  ...tseslint.configs.strictTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname
      }
    },
    rules: {
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "@typescript-eslint/restrict-template-expressions": "off",
      "no-console": "error"
    }
  }
);
