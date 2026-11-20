import { coreServices, createBackendModule } from '@backstage/backend-plugin-api';
import { scaffolderActionsExtensionPoint } from '@backstage/plugin-scaffolder-node';
import { createNamespaceAvailableAction } from './actions';
import { createRouter } from './router';

const namespaceValidatorPlugin = createBackendModule({
  moduleId: 'namespace-validator',
  pluginId: 'scaffolder',
  register(env) {
    env.registerInit({
      deps: {
        httpAuth: coreServices.httpAuth,
        httpRouter: coreServices.httpRouter,
        logger: coreServices.logger,
        scaffolderActions: scaffolderActionsExtensionPoint,
      },
      async init({ httpAuth, httpRouter, logger, scaffolderActions }) {
        httpRouter.use(createRouter({ httpAuth, logger }));
        scaffolderActions.addActions(createNamespaceAvailableAction());
      },
    });
  },
});

export default namespaceValidatorPlugin;
