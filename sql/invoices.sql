BEGIN;

CREATE TABLE public.invoices (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    issuer_id text NOT NULL
        CHECK (issuer_id ~ '^[a-z0-9_-]{1,40}$'),

    order_id uuid NOT NULL,

    currency text NOT NULL
        CHECK (currency = 'PEN'),

    items jsonb NOT NULL
        CHECK (
            jsonb_typeof(items) = 'array'
            AND jsonb_array_length(items) BETWEEN 1 AND 6
        ),

    total_cents bigint NOT NULL
        CHECK (total_cents BETWEEN 0 AND 30000000000),

    status text NOT NULL DEFAULT 'issued'
        CHECK (status = 'issued'),

    request_hash text NOT NULL
        CHECK (request_hash ~ '^[0-9a-f]{64}$'),

    created_at timestamptz NOT NULL DEFAULT now(),

    CONSTRAINT invoices_issuer_order_unique
        UNIQUE (issuer_id, order_id)
);

ALTER TABLE public.invoices
ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.invoices
FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT, INSERT
ON TABLE public.invoices
TO service_role;

COMMIT;
