import BaseRoute from "./baseRoute";

export const KEYCLOAK_CALLBACK = "/keycloak-callback";

class KeycloakCallbackRoute extends BaseRoute {
  isTokenRequired = false;

  page = "KeycloakCallback";

  link = KEYCLOAK_CALLBACK;

  layout = null;
}

export default new KeycloakCallbackRoute();
