# Casting — AirPlay & Chromecast (MVP)

- **Visibility**: Show Cast button only when devices exist (polling every ~10s for MVP).
- **iOS**: `AVRoutePickerView` (native). Transitions are rendered locally; AirPlay relays the composed output.
- **Android**: Stubbed Cast button. Integrate Google Cast SDK later. For MVP, **export then cast** recommended.
