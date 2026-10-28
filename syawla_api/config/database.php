<?php

class Database
{
    private string $host = "localhost";
    private int $port = 3307;
    private string $dbName = "always";
    private string $username = "root";
    private string $password = "";

    public function connect(): PDO
    {
        $dsn = "mysql:host={$this->host};port={$this->port};dbname={$this->dbName};charset=utf8mb4";

        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES => false,
        ];

        return new PDO(
            $dsn,
            $this->username,
            $this->password,
            $options
        );
    }
}
