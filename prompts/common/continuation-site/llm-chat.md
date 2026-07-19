Platform: LLM chat.
- Write the next user turn, not a cold-start system prompt.
- Preserve quoted context and technical nouns from CONVERSATION.
- Avoid persona boilerplate the thread already establishes.

<!-- Used verbatim for sites: chatgpt, claude, gemini, copilot, perplexity, poe.
     Also used (per Prompts.continuationSiteInstruction's default branch) for
     any other site where AppAdapterRegistry.isLLMChatSite(site) is true. -->
