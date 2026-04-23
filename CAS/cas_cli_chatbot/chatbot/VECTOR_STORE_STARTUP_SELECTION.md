# Vector Store Startup Selection Feature

## Overview
This feature prompts users to select a vector store when the CLI starts, improving the user experience by ensuring they have a vector store configured before attempting queries.

## Implementation Details

### New Method: `_prompt_vector_store_selection()`
Located in `chatbot/cli/chatbot_cli.py`, this method handles the vector store selection flow at startup.

### Flow Logic

1. **Check for Available Vector Stores**
   - Fetches all vector stores from the namespace
   - If none found, displays a warning and returns

2. **Check Default Vector Store from Config**
   - If `default_vector_store` is set in `config.yaml`:
     - **Valid & Accessible**: Prompts user to confirm using it
     - **Valid but No Access**: Informs user they need access via Fusion UI
     - **Invalid**: Notifies user the vector store doesn't exist

3. **Display Available Vector Stores**
   - Uses existing `cmd_vector_stores_list()` function to show:
     - All vector stores in the namespace
     - Which ones the user has access to (✓ green)
     - Which ones they don't have access to (✗ red/dim)

4. **Prompt for Selection**
   - If user has accessible stores:
     - Asks if they want to select one now
     - Provides fuzzy search autocomplete
     - Validates selection and access
   - If user has no accessible stores:
     - Informs them to request access via Fusion UI
     - Provides guidance on using 'vector-stores list' command

5. **Handle User Selection**
   - **Accessible Store Selected**: Sets as current and confirms
   - **Inaccessible Store Selected**: Warns user and suggests Fusion UI
   - **Invalid Store**: Shows error message
   - **No Selection/Skip**: Allows user to continue without selection

### Integration Points

#### Startup Flow (main.py → chatbot_cli.py)
```
display_welcome()
    ↓
_prompt_vector_store_selection()  ← NEW
    ↓
Main CLI loop
```

#### Error Handling
- **KeyboardInterrupt**: Gracefully skips selection
- **General Exceptions**: Logs warning and allows continuation

### User Experience Scenarios

#### Scenario 1: User with Default Vector Store (Accessible)
```
Default vector store from configuration: vs-123
Use this vector store? [Y/n]: y
✓ Using vector store: vs-123
```

#### Scenario 2: User with Default Vector Store (No Access)
```
⚠ Default vector store 'production-data' found in config, but you don't have access to it.
To gain access, please assign your user to this vector store in the Fusion UI.

Available Vector Stores:
Vector Stores (5 total, 2 accessible)
✓ dev-testing (accessible)
✓ vs-123 (accessible)
✗ production-data (no access)
...
```

#### Scenario 3: New User (No Default)
```
Available Vector Stores:
Vector Stores (3 total, 2 accessible)
✓ dev-testing (accessible)
✓ vs-123 (accessible)
✗ restricted-store (no access)

You have access to 2 vector store(s).
Would you like to select a vector store now? [Y/n]: y
Select vector store (type to search, or press Ctrl+C to skip): vs-123
✓ Selected vector store: vs-123
```

#### Scenario 4: User Selects Inaccessible Store
```
Select vector store: restricted-store
⚠ You selected 'restricted-store' but don't have access to it.
To gain access, please assign your user to this vector store in the Fusion UI.
You can select a different vector store using 'vector stores select' command.
```

#### Scenario 5: User with No Access to Any Store
```
⚠ You don't have access to any vector stores.
To gain access, please assign your user to a vector store in the Fusion UI.
You can view all vector stores using 'vector stores list' command.
```

## Configuration

### config.yaml
```yaml
default_vector_store: vs-123  # Optional: Set default vector store
cas_namespace: ibm-cas              # Namespace to search for vector stores
```

## Commands Available After Startup

Users can always change their vector store selection using:
- `vector stores list` - View all available vector stores
- `vector stores select` - Interactively select a vector store
- `vector stores select <name>` - Directly select a specific vector store

## Benefits

1. **Improved UX**: Users are guided to select a vector store before attempting queries
2. **Clear Access Information**: Users immediately see which stores they can access
3. **Fusion UI Integration**: Clear guidance on how to request access
4. **Flexible**: Users can skip selection and choose later
5. **Reuses Existing Code**: Leverages `cmd_vector_stores_list()` for consistency

## Technical Notes

- The method returns `bool` indicating if a vector store was successfully selected
- Uses `rich.prompt.Confirm` for yes/no prompts
- Integrates with existing `_accessible_vector_stores()` method
- Handles all edge cases gracefully with appropriate user feedback