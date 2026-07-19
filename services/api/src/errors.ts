import type { FastifyReply } from "fastify";
import type { ErrorCode } from "@writerflow/shared";

/** Shape matches Docs/contracts/openapi.yaml's Error schema exactly — top-level fields, not nested under "error". */
export interface ErrorBody {
  code: ErrorCode;
  message: string;
  requestId?: string;
}

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly statusCode: number;

  constructor(code: ErrorCode, statusCode: number, message: string) {
    super(message);
    this.code = code;
    this.statusCode = statusCode;
  }
}

export function sendError(reply: FastifyReply, error: ApiError): void {
  const body: ErrorBody = { code: error.code, message: error.message, requestId: reply.request.id };
  reply.code(error.statusCode).send(body);
}
