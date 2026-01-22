#!/bin/bash
# IdM User Import Script from JSON

# Check if running on IdM server or client with proper credentials
if ! command -v ipa &> /dev/null; then
    echo "Error: IPA command not found. Run this on IdM server or enrolled client."
    exit 1
fi

# Check if JSON file is provided
if [ -z "$1" ]; then
    echo "Usage: $0 <users.json> [default_password]"
    echo ""
    echo "JSON format example:"
    echo '['
    echo '  {'
    echo '    "id": 1,'
    echo '    "first_name": "John",'
    echo '    "last_name": "Doe",'
    echo '    "email": "jdoe@example.com"'
    echo '  }'
    echo ']'
    echo ""
    echo "Note: Usernames will be auto-generated as u + 4-digit ID"
    echo "      (e.g., id=1 -> u0001, id=123 -> u0123, id=1000 -> u1000)"
    exit 1
fi

JSON_FILE="$1"
DEFAULT_PASSWORD="${2:-pegadaian}"

# Check if JSON file exists
if [ ! -f "$JSON_FILE" ]; then
    echo "Error: File '$JSON_FILE' not found"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "Installing jq (JSON processor)..."
    if command -v apt &> /dev/null; then
        sudo apt install -y jq
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y jq
    else
        echo "Error: Please install jq manually"
        exit 1
    fi
fi

# Check Kerberos ticket
if ! klist &> /dev/null; then
    echo "Error: No valid Kerberos ticket found"
    echo "Please run: kinit admin"
    exit 1
fi

echo "=========================================="
echo "  IdM User Import Script"
echo "=========================================="
echo ""
echo "JSON File: $JSON_FILE"
echo "Default Password: $DEFAULT_PASSWORD"
echo ""

# Count total users
TOTAL_USERS=$(jq 'length' "$JSON_FILE")
echo "Found $TOTAL_USERS users to import"
echo ""

read -p "Continue with import? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Import cancelled"
    exit 0
fi

echo ""
echo "Starting import..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

# Process each user
for i in $(seq 0 $((TOTAL_USERS - 1))); do
    # Extract user data
    USER_ID=$(jq -r ".[$i].id" "$JSON_FILE")
    FIRST_NAME=$(jq -r ".[$i].first_name" "$JSON_FILE")
    LAST_NAME=$(jq -r ".[$i].last_name" "$JSON_FILE")
    EMAIL=$(jq -r ".[$i].email" "$JSON_FILE")

    # Generate username as u + 4-digit ID (e.g., u0001, u0123, u1000)
    if [ "$USER_ID" != "null" ] && [ -n "$USER_ID" ]; then
        USERNAME=$(printf "u%04d" "$USER_ID")
    else
        USERNAME=""
    fi

    # Validate required fields
    if [ -z "$USERNAME" ]; then
        echo "[$((i+1))/$TOTAL_USERS] ⚠️  Skipping: Cannot generate username (missing ID)"
        ((SKIP_COUNT++))
        continue
    fi

    if [ "$FIRST_NAME" = "null" ] || [ -z "$FIRST_NAME" ]; then
        echo "[$((i+1))/$TOTAL_USERS] ⚠️  Skipping $USERNAME: Missing first name"
        ((SKIP_COUNT++))
        continue
    fi

    if [ "$LAST_NAME" = "null" ] || [ -z "$LAST_NAME" ]; then
        echo "[$((i+1))/$TOTAL_USERS] ⚠️  Skipping $USERNAME: Missing last name"
        ((SKIP_COUNT++))
        continue
    fi

    # Check if user already exists
    if ipa user-show "$USERNAME" &> /dev/null; then
        echo "[$((i+1))/$TOTAL_USERS] ⏭️  User '$USERNAME' already exists, skipping..."
        ((SKIP_COUNT++))
        continue
    fi

    # Build ipa user-add command
    IPA_CMD="ipa user-add $USERNAME --first=\"$FIRST_NAME\" --last=\"$LAST_NAME\""

    if [ "$EMAIL" != "null" ] && [ -n "$EMAIL" ]; then
        IPA_CMD="$IPA_CMD --email=\"$EMAIL\""
    fi

    # Add user
    if eval "$IPA_CMD" &> /dev/null; then
        # Set default password
        echo "$DEFAULT_PASSWORD" | ipa passwd "$USERNAME" --password &> /dev/null

        echo "[$((i+1))/$TOTAL_USERS] ✅ Created: $USERNAME ($FIRST_NAME $LAST_NAME)"
        ((SUCCESS_COUNT++))
    else
        echo "[$((i+1))/$TOTAL_USERS] ❌ Failed: $USERNAME"
        ((FAIL_COUNT++))
    fi
done

echo ""
echo "=========================================="
echo "  Import Summary"
echo "=========================================="
echo "Total users in file: $TOTAL_USERS"
echo "Successfully created: $SUCCESS_COUNT"
echo "Failed: $FAIL_COUNT"
echo "Skipped: $SKIP_COUNT"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "Default password for new users: $DEFAULT_PASSWORD"
    echo "Users will be required to change password on first login"
fi

echo ""
echo "Import complete!"
