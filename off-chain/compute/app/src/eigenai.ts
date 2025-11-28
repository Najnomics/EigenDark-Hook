/**
 * EigenAI Grant API Integration
 * 
 * This module provides wallet-based authentication for EigenAI using the
 * deTERMinal grant system. Instead of API keys, users sign messages with their
 * wallet to authenticate requests.
 * 
 * Documentation: https://github.com/scotthconner/eigenx-determinal-token-grants
 */

import { privateKeyToAccount } from "viem/accounts";
import { signMessage } from "viem";
import axios, { AxiosInstance } from "axios";
import { logger } from "./logger.js";

const SERVER_URL = "https://determinal-api.eigenarcade.com";

export interface GrantMessageResponse {
  success: boolean;
  message: string;
  address: string;
}

export interface GrantStatusResponse {
  success: boolean;
  tokenCount: number;
  address: string;
  hasGrant: boolean;
}

export interface ChatCompletionRequest {
  messages: Array<{ role: string; content: string }>;
  model: string;
  max_tokens?: number;
  seed?: number;
  temperature?: number;
  grantMessage: string;
  grantSignature: string;
  walletAddress: string;
}

export interface ChatCompletionResponse {
  id: string;
  created: number;
  model: string;
  object: string;
  choices: Array<{
    index: number;
    message: {
      role: string;
      content: string;
    };
    finish_reason: string;
  }>;
  usage: {
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
  };
  signature?: string;
}

export class EigenAIClient {
  private privateKey: `0x${string}`;
  private walletAddress: `0x${string}`;
  private httpClient: AxiosInstance;

  constructor(privateKey: `0x${string}`, walletAddress: `0x${string}`) {
    this.privateKey = privateKey;
    this.walletAddress = walletAddress;
    this.httpClient = axios.create({
      baseURL: SERVER_URL,
      timeout: 60000, // 60 seconds for AI inference
      headers: {
        "Content-Type": "application/json",
      },
    });
  }

  /**
   * Get a grant message to sign for authentication
   */
  async getGrantMessage(): Promise<string> {
    try {
      const response = await this.httpClient.get<GrantMessageResponse>("/message", {
        params: { address: this.walletAddress },
      });

      if (!response.data.success) {
        throw new Error("Failed to get grant message");
      }

      logger.info({ address: this.walletAddress }, "Grant message retrieved");
      return response.data.message;
    } catch (error) {
      logger.error({ err: (error as Error).message }, "Failed to get grant message");
      throw error;
    }
  }

  /**
   * Check if the wallet has an active grant
   */
  async checkGrant(): Promise<GrantStatusResponse> {
    try {
      const response = await this.httpClient.get<GrantStatusResponse>("/checkGrant", {
        params: { address: this.walletAddress },
      });

      logger.info(
        { address: this.walletAddress, tokenCount: response.data.tokenCount, hasGrant: response.data.hasGrant },
        "Grant status checked",
      );
      return response.data;
    } catch (error) {
      logger.error({ err: (error as Error).message }, "Failed to check grant status");
      throw error;
    }
  }

  /**
   * Sign a message with the wallet's private key
   */
  async signMessage(message: string): Promise<`0x${string}`> {
    try {
      const account = privateKeyToAccount(this.privateKey);
      const signature = await signMessage({
        account,
        message,
      });
      return signature;
    } catch (error) {
      logger.error({ err: (error as Error).message }, "Failed to sign message");
      throw error;
    }
  }

  /**
   * Get authenticated grant message and signature
   */
  async getAuthenticatedGrant(): Promise<{ message: string; signature: `0x${string}` }> {
    const message = await this.getGrantMessage();
    const signature = await this.signMessage(message);
    return { message, signature };
  }

  /**
   * Make a chat completion request to EigenAI
   */
  async chatCompletions(
    userMessage: string,
    options: {
      model?: string;
      max_tokens?: number;
      seed?: number;
      temperature?: number;
    } = {},
  ): Promise<ChatCompletionResponse> {
    try {
      // Get authenticated grant
      const { message: grantMessage, signature: grantSignature } = await this.getAuthenticatedGrant();

      const request: ChatCompletionRequest = {
        messages: [{ role: "user", content: userMessage }],
        model: options.model || "gpt-oss-120b-f16",
        max_tokens: options.max_tokens || 150,
        seed: options.seed,
        temperature: options.temperature,
        grantMessage,
        grantSignature,
        walletAddress: this.walletAddress,
      };

      logger.info({ model: request.model, max_tokens: request.max_tokens }, "Making EigenAI chat completion request");

      const response = await this.httpClient.post<ChatCompletionResponse>("/api/chat/completions", request);

      logger.info(
        {
          model: response.data.model,
          tokens: response.data.usage.total_tokens,
          hasSignature: !!response.data.signature,
        },
        "EigenAI chat completion successful",
      );

      return response.data;
    } catch (error) {
      logger.error({ err: (error as Error).message }, "EigenAI chat completion failed");
      throw error;
    }
  }
}

/**
 * Create an EigenAI client instance
 */
export function createEigenAIClient(privateKey: `0x${string}`, walletAddress: `0x${string}`): EigenAIClient {
  return new EigenAIClient(privateKey, walletAddress);
}

