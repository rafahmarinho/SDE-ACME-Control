export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code: string = 'error',
    public readonly details?: unknown,
  ) {
    super(message);
    this.name = 'ApiError';
  }

  toJSON() {
    return { error: this.code, message: this.message, details: this.details ?? null };
  }
}

export const unauthorized = (message = 'Authentication required') => new ApiError(401, message, 'unauthorized');
export const forbidden = (message = 'You are not allowed to perform this action') => new ApiError(403, message, 'forbidden');
export const notFound = (message = 'Not found') => new ApiError(404, message, 'not_found');
export const badRequest = (message: string, details?: unknown) => new ApiError(400, message, 'bad_request', details);
export const conflict = (message: string, details?: unknown) => new ApiError(409, message, 'rejected', details);
