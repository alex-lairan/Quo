-- Quo Demo Database Setup
-- Run: psql -d quo_demo -f examples/setup_pg.sql

-- Drop existing tables (in reverse order of dependencies)
DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS inventory CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS transfers CASCADE;
DROP TABLE IF EXISTS accounts CASCADE;
DROP TABLE IF EXISTS posts CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- Users table
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    role VARCHAR(50) DEFAULT 'user',
    tier VARCHAR(50) DEFAULT 'free',
    status VARCHAR(50) DEFAULT 'pending',
    active BOOLEAN DEFAULT true,
    balance_cents BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Accounts table (for transfers)
CREATE TABLE accounts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    name VARCHAR(255) NOT NULL,
    balance BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Transfers table
CREATE TABLE transfers (
    id BIGSERIAL PRIMARY KEY,
    from_account BIGINT REFERENCES accounts(id),
    to_account BIGINT REFERENCES accounts(id),
    amount BIGINT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Posts table
CREATE TABLE posts (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    body TEXT,
    status VARCHAR(50) DEFAULT 'draft',
    view_count BIGINT DEFAULT 0,
    published_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Categories table (for recursive CTE demo)
CREATE TABLE categories (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    parent_id BIGINT REFERENCES categories(id),
    level INT DEFAULT 0
);

-- Products table
CREATE TABLE products (
    id BIGSERIAL PRIMARY KEY,
    category_id BIGINT REFERENCES categories(id),
    name VARCHAR(255) NOT NULL,
    price_cents BIGINT NOT NULL,
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Inventory table
CREATE TABLE inventory (
    id BIGSERIAL PRIMARY KEY,
    product_id BIGINT UNIQUE REFERENCES products(id),
    quantity BIGINT DEFAULT 0,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Orders table
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT REFERENCES users(id),
    status VARCHAR(50) DEFAULT 'pending',
    total_cents BIGINT DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Order items table
CREATE TABLE order_items (
    id BIGSERIAL PRIMARY KEY,
    order_id BIGINT REFERENCES orders(id),
    product_id BIGINT REFERENCES products(id),
    quantity INT NOT NULL,
    price_cents BIGINT NOT NULL
);

-- Insert sample data

-- Users
INSERT INTO users (name, email, role, tier, status, active) VALUES
    ('Alice Admin', 'alice@example.com', 'admin', 'premium', 'active', true),
    ('Bob Builder', 'bob@example.com', 'user', 'premium', 'active', true),
    ('Carol Customer', 'carol@example.com', 'user', 'free', 'active', true),
    ('Dave Developer', 'dave@example.com', 'moderator', 'premium', 'active', true),
    ('Eve Explorer', 'eve@example.com', 'user', 'free', 'pending', true),
    ('Frank Free', 'frank@example.com', 'user', 'free', 'active', false),
    ('Grace Guest', 'grace@example.com', 'guest', 'free', 'active', true);

-- Accounts
INSERT INTO accounts (user_id, name, balance) VALUES
    (1, 'Alice Checking', 50000),
    (1, 'Alice Savings', 100000),
    (2, 'Bob Checking', 25000),
    (3, 'Carol Checking', 15000);

-- Posts
INSERT INTO posts (user_id, title, body, status, view_count, published_at) VALUES
    (1, 'Getting Started with Quo', 'Learn the basics...', 'published', 1500, NOW() - INTERVAL '10 days'),
    (1, 'Advanced Queries', 'Deep dive into...', 'published', 3200, NOW() - INTERVAL '5 days'),
    (2, 'My First Post', 'Hello world!', 'published', 450, NOW() - INTERVAL '3 days'),
    (2, 'Draft Ideas', 'Work in progress...', 'draft', 0, NULL),
    (3, 'Customer Story', 'How I use Quo...', 'published', 890, NOW() - INTERVAL '1 day'),
    (4, 'Moderator Tips', 'Best practices...', 'published', 2100, NOW() - INTERVAL '7 days');

-- Categories (hierarchical)
INSERT INTO categories (id, name, parent_id, level) VALUES
    (1, 'Electronics', NULL, 0),
    (2, 'Computers', 1, 1),
    (3, 'Laptops', 2, 2),
    (4, 'Desktops', 2, 2),
    (5, 'Phones', 1, 1),
    (6, 'Smartphones', 5, 2),
    (7, 'Accessories', 1, 1),
    (8, 'Clothing', NULL, 0),
    (9, 'Men', 8, 1),
    (10, 'Women', 8, 1);

-- Products
INSERT INTO products (category_id, name, price_cents, active) VALUES
    (3, 'MacBook Pro', 249900, true),
    (3, 'ThinkPad X1', 189900, true),
    (4, 'Gaming PC', 149900, true),
    (6, 'iPhone 15', 99900, true),
    (6, 'Pixel 8', 79900, true),
    (7, 'USB-C Hub', 4900, true),
    (7, 'Wireless Mouse', 2900, true),
    (9, 'T-Shirt', 2500, true),
    (10, 'Dress', 7500, true);

-- Inventory
INSERT INTO inventory (product_id, quantity) VALUES
    (1, 50),
    (2, 30),
    (3, 25),
    (4, 100),
    (5, 75),
    (6, 200),
    (7, 150),
    (8, 500),
    (9, 300);

-- Orders
INSERT INTO orders (user_id, status, total_cents, created_at) VALUES
    (2, 'completed', 254800, NOW() - INTERVAL '30 days'),
    (2, 'completed', 99900, NOW() - INTERVAL '20 days'),
    (2, 'completed', 7800, NOW() - INTERVAL '10 days'),
    (3, 'completed', 189900, NOW() - INTERVAL '25 days'),
    (3, 'pending', 104800, NOW() - INTERVAL '1 day'),
    (4, 'completed', 249900, NOW() - INTERVAL '15 days'),
    (4, 'completed', 82800, NOW() - INTERVAL '5 days'),
    (5, 'pending', 2500, NOW());

-- Order items
INSERT INTO order_items (order_id, product_id, quantity, price_cents) VALUES
    (1, 1, 1, 249900),
    (1, 6, 1, 4900),
    (2, 4, 1, 99900),
    (3, 6, 1, 4900),
    (3, 7, 1, 2900),
    (4, 2, 1, 189900),
    (5, 4, 1, 99900),
    (5, 6, 1, 4900),
    (6, 1, 1, 249900),
    (7, 5, 1, 79900),
    (7, 7, 1, 2900),
    (8, 8, 1, 2500);

-- Create indexes for performance
CREATE INDEX idx_users_status ON users(status);
CREATE INDEX idx_users_role ON users(role);
CREATE INDEX idx_posts_user_id ON posts(user_id);
CREATE INDEX idx_posts_status ON posts(status);
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_categories_parent_id ON categories(parent_id);

SELECT 'Setup complete!' AS message;
SELECT 'Users: ' || COUNT(*) FROM users;
SELECT 'Posts: ' || COUNT(*) FROM posts;
SELECT 'Products: ' || COUNT(*) FROM products;
SELECT 'Orders: ' || COUNT(*) FROM orders;
