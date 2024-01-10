declare global {
    namespace NodeJS {
        interface ProcessEnv {
            GOOGLE_APPLICATION_CREDENTIALS: string;
            OPENAI_API_KEY: string;
        }
    }
}

export {};
