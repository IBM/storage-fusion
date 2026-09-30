import { InputError } from '@backstage/errors';
import { createTemplateAction } from '@backstage/plugin-scaffolder-node';
import { namespaceExists, namespaceName } from './kubernetes';

export function createNamespaceAvailableAction() {
  return createTemplateAction({
    id: 'naas:namespace:available',
    description: 'Fails when the requested OpenShift namespace already exists.',
    schema: {
      input: {
        projectName: z => z.string().min(1),
        environment: z => z.string().min(1),
      },
    },
    async handler(ctx) {
      const name = namespaceName(ctx.input.projectName, ctx.input.environment);

      if (await namespaceExists(name)) {
        throw new InputError(`Namespace "${name}" already exists.`);
      }

      ctx.output('namespace', name);
      ctx.output('available', true);
    },
  });
}
