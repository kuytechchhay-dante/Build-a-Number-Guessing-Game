#!/bin/bash

PSQL=(psql -X -U freecodecamp -d number_guess -qAt -v ON_ERROR_STOP=1)

printf '%s\n' 'Enter your username:'
IFS= read -r username || exit 0

if ! player=$("${PSQL[@]}" -v username="$username" <<'SQL'
SELECT u.user_id, COUNT(g.game_id), COALESCE(MIN(g.guesses), 0)
FROM users AS u
LEFT JOIN games AS g USING (user_id)
WHERE u.username = :'username'
GROUP BY u.user_id;
SQL
); then
  exit 1
fi

if [[ -n $player ]]; then
  IFS='|' read -r user_id games_played best_game <<< "$player"
  printf 'Welcome back, %s! You have played %s games, and your best game took %s guesses.\n' \
    "$username" "$games_played" "$best_game"
else
  if ! user_id=$("${PSQL[@]}" -v username="$username" <<'SQL'
INSERT INTO users (username)
VALUES (:'username')
ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username
RETURNING user_id;
SQL
  ); then
    exit 1
  fi
  printf 'Welcome, %s! It looks like this is your first time here.\n' "$username"
fi

secret_number=$((RANDOM % 1000 + 1))
guesses=0

printf '%s\n' 'Guess the secret number between 1 and 1000:'

while IFS= read -r guess; do
  ((guesses += 1))

  if [[ ! $guess =~ ^[+-]?[0-9]+$ ]]; then
    printf '%s\n' 'That is not an integer, guess again:'
  elif [[ $guess == -* ]]; then
    printf '%s\n' "It's higher than that, guess again:"
  else
    # Strip a plus sign and leading zeros before comparing in base 10.
    [[ $guess =~ ^[+]?0*([0-9]+)$ ]]
    number=${BASH_REMATCH[1]}

    if [[ ${#number} -gt 4 ]] || (( number > secret_number )); then
      printf '%s\n' "It's lower than that, guess again:"
    elif (( number < secret_number )); then
      printf '%s\n' "It's higher than that, guess again:"
    else
      if ! "${PSQL[@]}" -v user_id="$user_id" -v guesses="$guesses" <<'SQL'
INSERT INTO games (user_id, guesses)
VALUES (:'user_id', :'guesses');
SQL
      then
        exit 1
      fi

      printf 'You guessed it in %s tries. The secret number was %s. Nice job!\n' \
        "$guesses" "$secret_number"
      exit 0
    fi
  fi
done
