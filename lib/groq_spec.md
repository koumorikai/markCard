# Groq AI Integration Specification — MarkCard

## 1. Project Overview

**Project:** MarkCard  
**Module:** Groq AI Integration  
**Platform:** Flutter  
**AI Provider:** Groq Cloud  
**API Type:** Chat Completions API

### Purpose

The Groq AI module generates educational flashcards from user-provided topics.

MarkCard helps users learn vocabulary, definitions, concepts, and terminology through active recall and spaced repetition.

The integration must provide reliable generation, structured JSON output, data validation, and seamless integration with the existing flashcard system.

The primary requirement is that every successful generation produces exactly 20 valid, unique flashcards.

## 2. Core Requirements

The module must:

- Generate flashcards from a user-defined topic.
- Generate exactly 20 flashcards per successful request.
- Support configurable source and target languages.
- Support configurable difficulty levels.
- Generate accurate definitions, translations, and contextual examples.
- Return structured JSON data.
- Parse API responses into Dart objects.
- Validate generated flashcards before saving.
- Detect and replace duplicate cards.
- Generate missing cards when the initial response contains fewer than 20 valid cards.
- Preview generated cards before saving.
- Integrate with existing MarkCard decks.
- Handle network errors, API failures, and malformed responses.
- Protect API credentials.

## 3. Groq API Configuration

### Endpoint

`https://api.groq.com/openai/v1/chat/completions`

### HTTP Method

`POST`

### Headers

```http
Content-Type: application/json
Authorization: Bearer ${GROQ_API_KEY}
```

### Model Configuration

The application must use a language model currently supported by Groq.

Suggested initial model:

`llama-3.3-70b-versatile`

This identifier must be verified against the current Groq model catalog before implementation. The model must be configurable without requiring changes to the UI.

### Request Parameters

| Parameter | Value | Purpose |
|---|---|---|
| model | Configurable | Selects the AI model |
| temperature | 0.5 | Controls response variability |
| messages | Array | Contains system and user prompts |
| response_format | JSON object | Requests structured JSON output when supported |

The implementation must use a response format supported by the selected model.

Because the required output contains an array, use a JSON object with a `flashcards` array.

## 4. User Input

The generation service accepts the following parameters:

- `topic`: the subject of the flashcards.
- `sourceLanguage`: the language used for terms or questions.
- `targetLanguage`: the language used for translations or explanations.
- `difficulty`: the required difficulty level.

The number of cards is not user-configurable. It is always 20.

### Example Input

```json
{
  "topic": "English Idioms",
  "sourceLanguage": "English",
  "targetLanguage": "Russian",
  "difficulty": "intermediate"
}
```

### Input Validation

Before sending a request:

- The topic must not be empty.
- The topic must not exceed 500 characters.
- The source language must be specified.
- The target language must be specified.
- The difficulty must be one of the supported values.
- The requested generation count must always equal 20 internally.

The UI must not allow users to reduce or increase the generation count.

## 5. AI Model Responsibilities

The selected Groq model must:

- Understand the requested learning topic.
- Generate relevant educational content.
- Produce accurate definitions and translations.
- Create useful contextual examples.
- Adapt content to the selected difficulty.
- Avoid repeated or nearly identical flashcards.
- Follow the requested language configuration.
- Return data in the required JSON structure.

The AI model is responsible for generating content. The application is responsible for validating that content.

## 6. System Prompt

Use the following system prompt as the baseline for flashcard generation.

```text
You are the AI flashcard generation engine for MarkCard.

Your task is to create exactly 20 high-quality educational
flashcards for the topic provided by the user.

Generation requirements:

1. Generate exactly 20 flashcards.
2. Every flashcard must teach one distinct learning objective.
3. Avoid duplicate and nearly identical flashcards.
4. Use the requested source language for the front field.
5. Use the requested target language for the back field.
6. Provide an accurate, concise, and useful definition or translation.
7. Include a relevant contextual example in every card.
8. Adapt the complexity to the requested difficulty.
9. Do not invent facts or provide misleading definitions.
10. Avoid unnecessary information and excessively long explanations.
11. Return valid JSON only.
12. Do not include Markdown fences or introductory text.
13. Do not include properties outside the required schema.

Return this exact JSON structure:

{
  "flashcards": [
    {
      "front": "Term, question, or concept",
      "back": "Definition or translation",
      "contextExample": "Example sentence or practical context"
    }
  ]
}

The flashcards array must contain exactly 20 objects.

All three properties must be non-empty strings.
Every card must be meaningfully different from the others.

Return only the JSON object.
```

The application must still validate the response because prompt instructions alone cannot guarantee the requested count or correctness.

## 7. Expected JSON Response

Example of the required response structure:

```json
{
  "flashcards": [
    {
      "front": "Break the ice",
      "back": "Разрядить обстановку и помочь людям почувствовать себя свободнее.",
      "contextExample": "He told a joke to break the ice at the meeting."
    },
    {
      "front": "Once in a blue moon",
      "back": "Очень редко.",
      "contextExample": "I eat fast food once in a blue moon."
    }
  ]
}
```

This example illustrates the schema only. A successful production response must contain exactly 20 valid flashcards.

## 8. Flashcard Data Model

MarkCard must use its existing flashcard model whenever possible.

The model must be compatible with the following AI-generated fields:

- `front`: term, question, or concept.
- `back`: definition or translation.
- `contextExample`: contextual example.

If the existing model includes additional properties such as `id`, `deckId`, `createdAt`, review statistics, or scheduling information, those properties must remain compatible with the existing application.

Do not replace the existing model with a simplified model that would break persistence or spaced repetition.

If the project does not yet have a suitable model, create one that supports JSON serialization and deserialization.

## 9. Service Architecture

Suggested project structure:

```text
lib/
├── models/
│   └── flashcard.dart
├── services/
│   └── groq_service.dart
├── repositories/
│   └── flashcard_repository.dart
├── screens/
│   └── generate_flashcards_screen.dart
├── widgets/
│   └── flashcard_preview.dart
└── config/
    └── app_config.dart

docs/
└── groq_integration_spec.md
```

This is a reference structure, not a requirement to duplicate existing files.

Adapt the implementation to MarkCard's current architecture and state-management approach.

### GroqService Responsibilities

The service must:

1. Accept generation parameters.
2. Build the API request.
3. Send the request to Groq.
4. Check the HTTP status code.
5. Extract the assistant response.
6. Parse the JSON.
7. Validate each flashcard.
8. Detect duplicate cards.
9. Generate missing cards when necessary.
10. Return exactly 20 valid, unique flashcards or throw a meaningful error.

The service must not directly manipulate Flutter widgets or display SnackBars.

### Repository Responsibilities

The repository must:

- Integrate generated cards with existing decks.
- Preserve existing cards.
- Save the new generation consistently.
- Prevent partial insertion where supported by the persistence layer.
- Handle persistence errors.

## 10. API Request Example

The following example illustrates the request structure.

```dart
final response = await http.post(
  Uri.parse(
    'https://api.groq.com/openai/v1/chat/completions',
  ),
  headers: {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $apiKey',
  },
  body: jsonEncode({
    'model': model,
    'temperature': 0.5,
    'messages': [
      {
        'role': 'system',
        'content': systemPrompt,
      },
      {
        'role': 'user',
        'content': userPrompt,
      },
    ],
    'response_format': {
      'type': 'json_object',
    },
  }),
);
```

The example assumes that the selected model supports the requested response format.

The actual implementation must include:

- A network timeout.
- HTTP status-code validation.
- JSON parsing.
- Response validation.
- Error handling.
- Secure credential management.

## 11. Response Parsing and Validation

The assistant response is extracted from:

`choices[0].message.content`

The implementation must perform the following steps:

1. Check that the HTTP request succeeded.
2. Check that the response contains a valid choice.
3. Extract the assistant's text content.
4. Decode the JSON.
5. Verify that the root is a JSON object.
6. Verify that `flashcards` exists and is an array.
7. Validate each flashcard.
8. Normalize text for duplicate detection.
9. Remove duplicate or invalid cards.
10. Count the remaining valid cards.
11. Generate missing cards if fewer than 20 remain.
12. Return the final list only when it contains exactly 20 valid, unique cards.

### Required Field Validation

Each card must contain:

- A non-empty `front` string.
- A non-empty `back` string.
- A non-empty `contextExample` string.

Incorrect types, missing properties, or blank strings must cause the affected card to be rejected.

The parser must not crash when the AI returns an unexpected structure.

## 12. Fixed Generation Count: Exactly 20 Cards

This requirement is mandatory.

### 12.1. Fixed Count

Every successful generation must produce exactly 20 flashcards.

- Minimum successful count: 20.
- Maximum successful count: 20.
- Default count: 20.
- User-configurable count: No.

The application must not report success with 19, 21, or any other number of cards.

### 12.2. Handling Fewer Than 20 Cards

If the initial response contains fewer than 20 valid, unique cards:

1. Preserve the valid cards temporarily.
2. Calculate how many additional cards are required.
3. Send a follow-up request asking only for the missing number.
4. Include the original topic, languages, and difficulty.
5. Tell the model which concepts have already been covered.
6. Reject duplicates of existing cards.
7. Validate the new cards.
8. Repeat only within the configured retry budget.

For example, if 16 valid cards remain, request 4 additional cards.

### 12.3. Handling More Than 20 Cards

If the model returns more than 20 valid cards:

- Validate all candidate cards.
- Remove duplicates.
- Select 20 appropriate, unique cards.
- Do not save additional cards from that generation.

### 12.4. Duplicate Detection

Duplicate detection must consider normalized text rather than exact string equality alone.

At minimum:

- Trim leading and trailing whitespace.
- Normalize repeated whitespace.
- Compare case-insensitively where appropriate.
- Compare normalized front fields.
- Avoid adding the same term or question twice.

Semantic similarity detection may be added if needed, but must not incorrectly reject distinct educational concepts.

### 12.5. Retry Policy

Use a bounded retry policy.

Suggested defaults:

- Initial generation attempts: 1.
- Additional completion attempts: Up to 2.
- Unlimited retries: Not allowed.

If exactly 20 valid cards cannot be produced within the retry budget:

- Do not save an incomplete set.
- Show a clear error message.
- Allow the user to retry the complete generation.
- Preserve the user's original input.

A failed generation must not be reported as successful.

## 13. Token and Response Limits

The selected model has context and output token limits.

The implementation must:

- Configure a reasonable output token budget.
- Account for the expected size of 20 flashcards.
- Keep prompts within the model's context limit.
- Detect truncated or incomplete responses.
- Handle token-limit errors without crashing.
- Avoid assuming that the requested number of cards was generated.

The output token budget must be configured according to the selected model's documented capabilities.

If the response is truncated, attempt bounded recovery or report a generation failure.

## 14. Error Handling

The integration must handle the following cases.

| Error | Expected behavior |
|---|---|
| Missing API key | Report a configuration error |
| HTTP 400 | Report an invalid request or unsupported parameter |
| HTTP 401 | Report invalid credentials |
| HTTP 403 | Report access or permission failure |
| HTTP 429 | Handle rate limits and quota errors |
| HTTP 5xx | Report a temporary provider failure |
| Network failure | Display a connection error |
| Request timeout | Allow the user to retry |
| Invalid JSON | Report a response-format error |
| Empty response | Report that no cards were generated |
| Invalid fields | Reject invalid cards |
| Duplicate cards | Remove duplicates and generate replacements |
| Fewer than 20 cards | Request missing cards within the retry budget |
| Incomplete generation | Do not save; report failure |
| Save failure | Preserve generated cards for retry where possible |

Error messages must not expose API keys, authorization headers, or sensitive server details.

## 15. User Interface Requirements

The generation screen must contain:

- A topic input field.
- A source language selector.
- A target language selector.
- A difficulty selector.
- A Generate button.
- A loading indicator.
- A generated-card preview.
- A Save action.
- A Cancel action.
- Appropriate success and error notifications.

There must be no card-count selector because the generation count is fixed at 20.

### Loading State

During generation:

- Display `CircularProgressIndicator`.
- Disable repeated generation requests.
- Prevent accidental duplicate submissions.
- Show a clear indication that 20 cards are being generated.
- Keep the UI responsive.

### Success State

When generation succeeds:

- Display all 20 cards for review.
- Allow the user to cancel or confirm saving.
- Preserve the full set until the user decides what to do.
- Show a success SnackBar only after the save operation succeeds.

### Error State

If generation fails:

- Display an understandable error message.
- Preserve the topic and generation settings.
- Provide a retry action.
- Do not display a partial set as a successful generation.

## 16. Saving and Persistence

Generated cards must be validated before being added to a MarkCard deck.

### Requirements

- Save exactly 20 cards per successful generation.
- Preserve existing flashcards.
- Avoid accidental duplicate insertion.
- Reuse the existing persistence mechanism.
- Preserve required deck IDs and metadata.
- Keep generation separate from storage.
- Handle persistence failures safely.

### Atomic Saving

Where supported by the database or repository, save the generation as a single logical transaction.

If saving fails, avoid leaving a partially inserted set.

If the persistence layer does not support transactions, implement an appropriate rollback or recovery strategy.

Do not discard the generated set merely because the first save attempt failed.

## 17. Security Requirements

**Never embed a production Groq API key in a distributed Flutter application.**

A key placed in source code, assets, or compiled configuration may be extracted.

For production:

1. Create a backend API using Flask, Django, or another suitable framework.
2. Store the Groq API key in a server-side environment variable or secrets manager.
3. Have Flutter send generation requests to the backend.
4. Validate user input on the backend.
5. Authenticate users where appropriate.
6. Apply per-user request limits.
7. Protect against abusive requests.
8. Never log API keys or authorization headers.
9. Configure timeouts and request-size limits.

For local development, environment configuration can simplify testing but does not make a key embedded in a distributed application secure.

## 18. Rate Limiting and Usage Control

The fixed limit of 20 cards applies to each successful generation, not to the user's lifetime total.

The backend should:

- Limit simultaneous generation requests per user.
- Configure daily or monthly request limits if needed.
- Respect the selected model's Groq rate limits.
- Handle HTTP 429 responses gracefully.
- Avoid unlimited retries.
- Record generation status without logging sensitive credentials.

Application-level limits must be configurable independently of provider-imposed limits.

## 19. Testing Requirements

### 19.1. Unit Tests

Test:

- Valid JSON parsing.
- Missing fields.
- Invalid field types.
- Empty strings.
- Empty arrays.
- Duplicate detection.
- Responses containing fewer than 20 cards.
- Responses containing more than 20 cards.
- Truncated JSON.
- Missing examples.
- Incorrect language or content fields where detectable.

### 19.2. Service Tests

Use mocked HTTP responses to test:

- Successful generation.
- Invalid API credentials.
- HTTP 429 responses.
- Server errors.
- Network failures.
- Request timeouts.
- Malformed responses.
- Missing-card recovery.
- Retry-budget exhaustion.

Automated tests must not require real Groq API calls.

### 19.3. UI Tests

Test:

- Empty topic validation.
- Language selection.
- Difficulty selection.
- Loading indicator behavior.
- Disabled Generate button during a request.
- Preview rendering.
- Saving exactly 20 cards.
- Error messages.
- Retry behavior.
- Prevention of partial saves.

## 20. Acceptance Criteria

The implementation is complete when all of the following are satisfied:

- [ ] Users can enter a learning topic.
- [ ] Source and target languages are configurable.
- [ ] Difficulty is configurable.
- [ ] The application always requests 20 cards.
- [ ] The UI does not allow changing the card count.
- [ ] Groq receives correctly formatted requests.
- [ ] API responses are parsed and validated.
- [ ] Duplicate cards are detected and replaced where possible.
- [ ] Missing cards are requested within the retry budget.
- [ ] A successful generation contains exactly 20 valid, unique cards.
- [ ] Incomplete generations are never reported as successful.
- [ ] Users can preview cards before saving.
- [ ] Existing MarkCard decks remain intact.
- [ ] Save failures are handled safely.
- [ ] Production API credentials are protected.
- [ ] Critical paths are covered by automated tests.

## 21. Implementation Plan

### Phase 1: Core API Integration

- Configure the Groq endpoint and model.
- Implement `GroqService`.
- Build the system and user prompts.
- Parse and validate JSON responses.

### Phase 2: Exact 20-Card Generation

- Fix the generation count at 20.
- Implement card validation.
- Implement duplicate detection.
- Implement missing-card generation.
- Add a bounded retry policy.
- Reject incomplete generations.

### Phase 3: UI Integration

- Connect generation to the MarkCard interface.
- Add loading and error states.
- Display the 20-card preview.
- Implement confirmation and cancellation.

### Phase 4: Persistence

- Integrate with existing decks.
- Preserve metadata and scheduling information.
- Prevent accidental duplicate insertion.
- Implement safe save and recovery behavior.

### Phase 5: Production Readiness

- Move API calls behind a secure backend.
- Add authentication and rate limiting as appropriate.
- Implement timeouts and monitoring.
- Add automated tests.
- Verify compatibility with the selected Groq model.

## 22. Final Implementation Principles

The Groq AI integration must be modular, secure, testable, and compatible with the existing MarkCard architecture.

The system must distinguish between AI generation and application-level validation.

The AI model cannot guarantee the requested number or quality of cards on its own. The application must validate the output and enforce the exact-count requirement.

A generation is successful only when exactly 20 valid, unique flashcards are ready for review.

The system must never silently save an incomplete generation or corrupt existing deck data.

Reuse existing MarkCard models, repositories, and state-management patterns wherever possible. Avoid unnecessary modifications to unrelated functionality.
