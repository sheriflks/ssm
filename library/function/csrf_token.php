<?php
class CSRFSecure
{
    public function __construct(){
        if(!isset($_SESSION['csrf'])) {
            $_SESSION['csrf'] = bin2hex(random_bytes(32));
        }
    }
    
    public function generate_token(){
        $_SESSION['csrf'] = bin2hex(random_bytes(32));
        return $_SESSION['csrf'];
    }
    
    public function show_tokenHTML(){ 
        return '<input type="hidden" name="csrf_token" id="csrf_token" value="'.$_SESSION['csrf'].'">'; 
    }
    
    public function show_tokenSTR(){ 
        return $_SESSION['csrf']; 
    }
    
    public function validateToken($token){
        if(!hash_equals($_SESSION['csrf'], $token)){
            $this->generate_token();
            return false;
        } else {
            $this->generate_token();
            return true;
        }
    }
}

$CSRFToken = new CSRFSecure();
$csrf_string = $_SESSION['csrf'];
$csrf_html = '<input type="hidden" id="csrf_token" name="csrf_token" value="'.$_SESSION['csrf'].'">';
if($_POST && !isset($_POST['csrf_token'])) {
    $result_csrf = false;
} else if($_POST && isset($_POST['csrf_token'])) {
    if(hash_equals($_SESSION['csrf'], $_POST['csrf_token']) == false) { $result_csrf = false; }
//	else if($CSRFToken->validateToken($_POST['csrf_token']) == false) { $result_csrf = false; }
	else { $result_csrf = true; }
}