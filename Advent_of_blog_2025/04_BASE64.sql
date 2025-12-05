-- BASE64_ENCODE()
-- BASE64_DECODE()


-- Encode
SELECT BASE64_ENCODE(CAST('hello world' AS varbinary));

-- Decode
SELECT CONVERT(VARCHAR(MAX) , BASE64_DECODE('aGVsbG8gd29ybGQ='))

 
 ---- or

 DECLARE 
    @plainText   nvarchar(100) = N'MyPl@inT3xt!',
    @encoded     varchar(max),
    @decodedBin  varbinary(max),
    @decodedText nvarchar(100);

-- 1) Encode (string -> varbinary -> Base64 varchar)
SET @encoded = BASE64_ENCODE(CAST(@plainText AS varbinary(max)));

-- 2) Decode (Base64 varchar -> varbinary)
SET @decodedBin = BASE64_DECODE(@encoded);

-- 3) Convert back to string
SET @decodedText = CAST(@decodedBin AS nvarchar(100));

SELECT 
    @plainText   AS OriginalText,
    @encoded     AS Base64Value,
    @decodedText AS DecodedText;
