import { getEnvironmentVariable } from "./env";

export const microsoftOAuthConfiguration = {
  auth: {
    clientId: getEnvironmentVariable("VITE_MICROSOFT_OAUTH_CLIENT_ID")
  }
};

const parseKeycloakAuthUrl = (authUrl: string | undefined) => {
  if (!authUrl) return { url: undefined, realm: undefined };

  try {
    const match = authUrl.match(/^(https?:\/\/[^/]+)\/realms\/([^/]+)/);
    if (match) {
      return { url: match[1], realm: match[2] };
    }
  } catch {
    // Fall through
  }
  return { url: authUrl, realm: undefined };
};

const keycloakUrl = getEnvironmentVariable("VITE_KEYCLOAK_URL");
const keycloakRealm = getEnvironmentVariable("VITE_KEYCLOAK_REALM");
const parsedFromUrl = keycloakUrl && !keycloakRealm ? parseKeycloakAuthUrl(keycloakUrl) : { url: keycloakUrl, realm: keycloakRealm };

export const keycloakOAuthConfiguration = {
  url: parsedFromUrl.url,
  realm: parsedFromUrl.realm,
  clientId: getEnvironmentVariable("VITE_KEYCLOAK_CLIENT_ID")
};
