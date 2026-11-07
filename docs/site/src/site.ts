// The version in the header badge: the repository's VERSION file (MAJOR.MINOR), read when the site
// is built so the badge can't drift from the app. A release appends its run number; the badge
// doesn't.
import version from '../../../VERSION?raw';

export const APP_VERSION = version.trim();
