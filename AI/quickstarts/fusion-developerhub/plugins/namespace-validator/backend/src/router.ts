import { InputError } from '@backstage/errors';
import type {
  HttpAuthService,
  LoggerService,
} from '@backstage/backend-plugin-api';
import { Router } from 'express';
import { namespaceExists, listGroups, listNaaSNamespaces, getNaaSNamespace } from './kubernetes';

const NAMESPACE_NAME_PATTERN = /^[a-z0-9]([-a-z0-9]*[a-z0-9])?$/;

export function createRouter(options: {
  httpAuth: HttpAuthService;
  logger: LoggerService;
}): Router {
  const router = Router();

  router.get('/namespaces/:name', async (request, response) => {
    try {
      await options.httpAuth.credentials(request, { allow: ['user'] });

      const { name } = request.params;
      if (!NAMESPACE_NAME_PATTERN.test(name) || name.length > 63) {
        throw new InputError('Namespace name must be a valid DNS label of at most 63 characters.');
      }

      const exists = await namespaceExists(name);
      response.json({ exists });
    } catch (error) {
      if (error instanceof InputError) {
        response.status(400).json({ error: { message: error.message } });
        return;
      }

      options.logger.error('Namespace availability check failed.', error as Error);
      response.status(503).json({
        error: { message: 'Namespace availability validation is unavailable.' },
      });
    }
  });

  router.get('/naas/namespaces', async (req, response) => {
    try {
      await options.httpAuth.credentials(req, { allow: ['user'] });

      const namespaces = await listNaaSNamespaces();
      response.json({ namespaces });
    } catch (error) {
      options.logger.error('NaaS namespace listing failed.', error as Error);
      response.status(503).json({
        error: { message: 'NaaS namespace listing is unavailable.' },
      });
    }
  });

  router.get('/naas/namespaces/:name', async (req, response) => {
    try {
      await options.httpAuth.credentials(req, { allow: ['user'] });

      const { name } = req.params;
      if (!NAMESPACE_NAME_PATTERN.test(name) || name.length > 63) {
        throw new InputError('Namespace name must be a valid DNS label of at most 63 characters.');
      }

      const metadata = await getNaaSNamespace(name);
      if (!metadata) {
        response.status(404).json({ error: { message: 'Namespace not found or not NaaS-managed.' } });
        return;
      }
      response.json(metadata);
    } catch (error) {
      if (error instanceof InputError) {
        response.status(400).json({ error: { message: error.message } });
        return;
      }
      options.logger.error('NaaS namespace fetch failed.', error as Error);
      response.status(503).json({
        error: { message: 'NaaS namespace lookup is unavailable.' },
      });
    }
  });

  router.get('/groups', async (request, response) => {
    try {
      await options.httpAuth.credentials(request, { allow: ['user'] });

      const groups = await listGroups();
      response.json({ groups });
    } catch (error) {
      options.logger.error('Groups listing failed.', error as Error);
      response.status(503).json({
        error: { message: 'Groups listing is unavailable.' },
      });
    }
  });

  return router;
}