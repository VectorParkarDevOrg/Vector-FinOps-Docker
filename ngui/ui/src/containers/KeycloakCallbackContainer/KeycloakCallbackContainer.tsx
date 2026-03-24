import { useEffect, useState } from "react";
import { useDispatch } from "react-redux";
import { useNavigate } from "react-router-dom";
import { CircularProgress, Box, Typography } from "@mui/material";
import { initialize } from "containers/InitializeContainer/redux";
import { useSignInMutation } from "graphql/__generated__/hooks/auth";
import { LOGIN, INITIALIZE } from "urls";
import { GA_EVENT_CATEGORIES, trackEvent } from "utils/analytics";
import { AUTH_PROVIDERS } from "utils/constants";
import macaroon from "utils/macaroons";

const KeycloakCallbackContainer = () => {
  const dispatch = useDispatch();
  const navigate = useNavigate();
  const [error, setError] = useState<string | null>(null);
  const [signIn] = useSignInMutation();

  useEffect(() => {
    const handleCallback = async () => {
      const urlParams = new URLSearchParams(window.location.search);
      const code = urlParams.get("code");
      const state = urlParams.get("state");
      const errorParam = urlParams.get("error");
      const errorDescription = urlParams.get("error_description");

      if (errorParam) {
        setError(errorDescription || errorParam);
        return;
      }

      const storedState = sessionStorage.getItem("keycloak_oauth_state");
      const codeVerifier = sessionStorage.getItem("keycloak_code_verifier");

      if (!code) {
        setError("No authorization code received");
        return;
      }

      if (state !== storedState) {
        setError("Invalid state parameter");
        return;
      }

      sessionStorage.removeItem("keycloak_oauth_state");
      sessionStorage.removeItem("keycloak_code_verifier");

      const redirectUri = `${window.location.origin}/keycloak-callback`;

      try {
        const { data } = await signIn({
          variables: {
            provider: AUTH_PROVIDERS.KEYCLOAK,
            token: code,
            redirectUri,
            codeVerifier
          }
        });

        const caveats = macaroon.processCaveats(macaroon.deserialize(data.signIn.token).getCaveats());

        if (caveats.register) {
          trackEvent({ category: GA_EVENT_CATEGORIES.USER, action: "Registered", label: "keycloak" });
        }

        dispatch(initialize({ ...data.signIn, caveats }));
        navigate(INITIALIZE);
      } catch (err: unknown) {
        console.error("Keycloak sign-in error:", err);
        const errorMessage = err instanceof Error ? err.message : String(err);
        if (errorMessage.includes("Network") || errorMessage.includes("fetch")) {
          setError("Unable to connect to authentication server. Please check your network connection.");
        } else if (errorMessage.includes("403") || errorMessage.includes("Forbidden")) {
          setError("Authentication was denied. Please contact your administrator.");
        } else if (errorMessage.includes("401") || errorMessage.includes("Unauthorized")) {
          setError("Invalid credentials. Please try signing in again.");
        } else if (errorMessage.includes("timeout") || errorMessage.includes("Timeout")) {
          setError("Authentication timed out. Please try again.");
        } else {
          setError("Authentication failed. Please try again or contact support.");
        }
      }
    };

    handleCallback();
  }, [dispatch, navigate, signIn]);

  if (error) {
    return (
      <Box
        display="flex"
        flexDirection="column"
        alignItems="center"
        justifyContent="center"
        minHeight="100vh"
        gap={2}
      >
        <Typography color="error" variant="h6">
          Authentication Error
        </Typography>
        <Typography color="textSecondary">{error}</Typography>
        <Typography
          component="a"
          href={LOGIN}
          sx={{ color: "primary.main", textDecoration: "underline", cursor: "pointer" }}
        >
          Return to login
        </Typography>
      </Box>
    );
  }

  return (
    <Box display="flex" flexDirection="column" alignItems="center" justifyContent="center" minHeight="100vh" gap={2}>
      <CircularProgress />
      <Typography>Authenticating with Keycloak...</Typography>
    </Box>
  );
};

export default KeycloakCallbackContainer;
