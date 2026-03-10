# Deep Link Quick Reference

## View parameter values and their required fields

| View | Required Params | Optional Params |
|---|---|---|
| `home` | — | `start_tab` |
| `hotels` | `destination`, `lat`, `lon` | `check_in`, `check_out`, `rooms`, `adults`, `children`, `child_ages` |
| `cars` | `destination` | `return_destination`, `pickup_date_time`, `return_date_time`, `age_criteria_met` |
| `parks` | `attraction_id` | — |
| `parks_search` | — | `destination`, `lat`, `lon`, `category` |
| `activities` | `destination`, `lat`, `lon` | `start_date`, `end_date` |
| `flights` | — | — |

## Date formats

- Hotels/Activities dates: `YYYY-MM-DD`
- Car rental date-times: `YYYY-MM-DDT_HH:MM`

## Attraction ID format

- Standard: `attr_<ATTRACTION_ID>`
- With custom prefix: `<your_label>__attr_<ATTRACTION_ID>`
- Local lookup: `references/attractions-and-identifiers.json` (refresh via `bash scripts/fetch-attractions.sh`)

## Parks search categories (URL-encode spaces)

- Amusement Park
- Museum
- Tour
- Water Park
- Zoo
- Aquarium
- Show
- Ski

## Location parameter rules

- `destination` + `lat` + `lon` are atomic for hotels, activities, and parks_search
- Provide all three or none
- `destination` is display-only; `lat`/`lon` drive the actual search
- Clients must provide their own geocoding solution

## Car rental locations

- Use named locations (e.g. airport codes): `"MCO - Orlando International Airport - Orlando United States"`
- Driver age verification (`age_criteria_met`) is the client's responsibility

## Supported languages

`en` | `es` | `fr` | `pt` | `zh`
