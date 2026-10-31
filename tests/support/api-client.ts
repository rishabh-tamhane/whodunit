export interface ApiTestResponse<Body> {
  body: Body;
  headers: Headers;
  status: number;
}

export function createApiTestClient(
  baseUrl: string,
  fetchImplementation: typeof fetch = fetch,
) {
  return {
    async request<Body>(
      path: string,
      init: RequestInit = {},
    ): Promise<ApiTestResponse<Body>> {
      const headers = new Headers(init.headers);
      headers.set("accept", "application/json");

      const response = await fetchImplementation(new URL(path, baseUrl), {
        ...init,
        headers,
      });

      return {
        body: (await response.json()) as Body,
        headers: response.headers,
        status: response.status,
      };
    },
  };
}
