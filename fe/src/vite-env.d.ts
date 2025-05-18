interface ImportMetaEnv {
  readonly VITE_CENTRIFUGO_ENDPOINT: string;
  readonly VITE_CENTRIFUGO_TOKEN: string;
  readonly VITE_CENTRIFUGO_CHANNEL: string;
  // more env variables...
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
