import { createHandler } from './handler.ts';
import { dependencies } from '../_shared/video_calls.ts';

// getUser validates the bearer JWT explicitly (including asymmetric Auth keys).
Deno.serve(createHandler(dependencies));
