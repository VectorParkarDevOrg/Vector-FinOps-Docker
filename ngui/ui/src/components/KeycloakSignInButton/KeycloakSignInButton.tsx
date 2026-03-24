import { useCallback, useEffect } from "react";
import ButtonLoader from "components/ButtonLoader";
import KeycloakIcon from "icons/KeycloakIcon";
import { AUTH_PROVIDERS } from "utils/constants";
import { keycloakOAuthConfiguration } from "utils/integrations";

const generateRandomState = () => {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join("");
};

const generateCodeVerifier = () => {
  const array = new Uint8Array(32);
  crypto.getRandomValues(array);
  return Array.from(array, (byte) => byte.toString(16).padStart(2, "0")).join("");
};

const generateCodeChallenge = async (verifier: string) => {
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const digest = await crypto.subtle.digest("SHA-256", data);
  const base64 = btoa(String.fromCharCode(...new Uint8Array(digest)));
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

const KeycloakSignInButton = ({ handleSignIn, isLoading, disabled }) => {
  const { url, realm, clientId } = keycloakOAuthConfiguration;

  const environmentNotSet = !url || !realm || !clientId;

  const handleClick = useCallback(async () => {
    if (environmentNotSet) return;

    const state = generateRandomState();
    const codeVerifier = generateCodeVerifier();
    const codeChallenge = await generateCodeChallenge(codeVerifier);

    sessionStorage.setItem("keycloak_oauth_state", state);
    sessionStorage.setItem("keycloak_code_verifier", codeVerifier);

    const redirectUri = `${window.location.origin}/keycloak-callback`;

    const authUrl = new URL(`${url}/realms/${realm}/protocol/openid-connect/auth`);
    authUrl.searchParams.set("client_id", clientId);
    authUrl.searchParams.set("redirect_uri", redirectUri);
    authUrl.searchParams.set("response_type", "code");
    authUrl.searchParams.set("scope", "openid email profile");
    authUrl.searchParams.set("state", state);
    authUrl.searchParams.set("code_challenge", codeChallenge);
    authUrl.searchParams.set("code_challenge_method", "S256");

    window.location.href = authUrl.toString();
  }, [url, realm, clientId, environmentNotSet]);

  useEffect(() => {
    const urlParams = new URLSearchParams(window.location.search);
    const code = urlParams.get("code");
    const state = urlParams.get("state");
    const storedState = sessionStorage.getItem("keycloak_oauth_state");
    const codeVerifier = sessionStorage.getItem("keycloak_code_verifier");

    if (code && state && storedState === state) {
      sessionStorage.removeItem("keycloak_oauth_state");
      sessionStorage.removeItem("keycloak_code_verifier");

      const redirectUri = `${window.location.origin}/keycloak-callback`;

      handleSignIn({
        provider: AUTH_PROVIDERS.KEYCLOAK,
        token: code,
        redirectUri,
        codeVerifier
      });

      window.history.replaceState({}, document.title, window.location.pathname);
    }
  }, [handleSignIn]);

  return (
    <ButtonLoader
      variant="outlined"
      messageId="keycloak"
      size="medium"
      onClick={handleClick}
      startIcon={<KeycloakIcon />}
      isLoading={isLoading}
      disabled={disabled || environmentNotSet}
      fullWidth
      tooltip={{
        show: environmentNotSet,
        messageId: "signInWithKeycloakIsNotConfigured"
      }}
    />
  );
};

export default KeycloakSignInButton;
