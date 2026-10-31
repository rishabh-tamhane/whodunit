# Module boundaries

Feature modules are added under this directory as their owning tasks begin:

- auth
- rooms
- gameplay
- story-generation
- interventions
- scoring
- projections

Each module keeps pure rules in a domain folder, use cases in an application
folder, and database or provider adapters in a server folder. Route handlers
validate transport input, call a use case, and serialize a projection. They do
not contain SQL, prompts, or provider logic.

The gameplay module cannot import the OpenAI SDK. The projections module is the
only module that shapes room state for clients.
