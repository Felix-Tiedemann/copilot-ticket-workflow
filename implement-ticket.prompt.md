---
name: implement-ticket
description: "Implement a Jira ticket end-to-end with research, plan approval, implementation, and review"
argument-hint: "<ticket key or URL> [depth=quick|normal|thorough]"
agent: ticket-orchestrator
---
Implement the Jira ticket given in the arguments, following your workflow including all approval gates.
Apply the `depth` from the arguments (default: `normal`) as defined in your Depth section.
