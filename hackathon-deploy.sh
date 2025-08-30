#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT_ID=""
REGION="us-central1"
CLUSTER_NAME="bank-of-anthos-hackathon"
ACTION=""
DEFAULT_PROJECT_ID="hackathon-gke-anthos-2025"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    cat << EOF
GKE Hackathon Deployment Script for Bank of Anthos

Usage: $0 -a ACTION [OPTIONS]

REQUIRED:
    -a ACTION        Action to perform: setup | deploy | status | destroy | all

OPTIONAL:
    -p PROJECT_ID    Google Cloud Project ID (default: hackathon-gke-anthos-2025)
    -r REGION        GKE region (default: us-central1)
    -c CLUSTER_NAME  Cluster name (default: bank-of-anthos-hackathon)

ACTIONS:
    setup      Enable APIs and create GKE Autopilot cluster
    deploy     Deploy Bank of Anthos to existing cluster  
    status     Check deployment status and get URLs
    destroy    Delete everything (cluster and resources)
    all        Run setup + deploy + status

EXAMPLES:
    # Complete deployment (uses default project ID)
    $0 -a all

    # Complete deployment with custom project
    $0 -p my-custom-project -a all

    # Just check status
    $0 -a status

    # Clean up everything
    $0 -a destroy

EOF
}

log_info() {
    echo -e "${GREEN}✓${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
    exit 1
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_step() {
    echo -e "\n${BLUE}▶${NC} $1"
}

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    local missing_tools=()
    
    command -v gcloud &> /dev/null || missing_tools+=("gcloud")
    command -v kubectl &> /dev/null || missing_tools+=("kubectl")
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
    fi
    
    if [ -z "$PROJECT_ID" ]; then
        PROJECT_ID="$DEFAULT_PROJECT_ID"
        log_info "Using default project ID: ${PROJECT_ID}"
    fi
    
    log_info "All prerequisites met"
}

create_or_use_project() {
    log_step "Setting up Google Cloud project '${PROJECT_ID}'..."
    
    # Check if project exists
    if gcloud projects describe ${PROJECT_ID} &> /dev/null; then
        log_info "Project '${PROJECT_ID}' already exists, using it"
    else
        log_info "Creating new project '${PROJECT_ID}'..."
        
        # Get current billing account
        local billing_account=$(gcloud billing accounts list --format="value(name)" --limit=1 2>/dev/null)
        
        if [ -z "$billing_account" ]; then
            log_warning "No billing account found!"
            echo ""
            echo "  💡 TIP: New to Google Cloud? Get $300 FREE credits:"
            echo "     https://cloud.google.com/free"
            echo ""
            echo "  The hackathon prizes include GCP credits for winners,"
            echo "  but you need your own account to participate."
            echo ""
            echo "  Please set up billing at:"
            echo "  https://console.cloud.google.com/billing"
            log_error "Billing account is required to create GKE clusters"
        fi
        
        # Create the project
        gcloud projects create ${PROJECT_ID} --name="${PROJECT_ID}"
        
        # Link billing account
        log_info "Linking billing account..."
        gcloud billing projects link ${PROJECT_ID} --billing-account=${billing_account}
        
        log_info "Project created successfully"
    fi
    
    # Set as active project
    gcloud config set project ${PROJECT_ID}
    log_info "Active project set to '${PROJECT_ID}'"
}

setup_gcloud() {
    create_or_use_project
    
    log_info "Enabling required APIs..."
    gcloud services enable \
        container.googleapis.com \
        compute.googleapis.com \
        artifactregistry.googleapis.com \
        --project=${PROJECT_ID}
    
    log_info "APIs enabled"
}

create_cluster() {
    log_step "Creating GKE Autopilot cluster '${CLUSTER_NAME}'..."
    
    if gcloud container clusters describe ${CLUSTER_NAME} \
        --region=${REGION} \
        --project=${PROJECT_ID} &> /dev/null; then
        log_warning "Cluster already exists, skipping creation"
    else
        gcloud container clusters create-auto ${CLUSTER_NAME} \
            --project=${PROJECT_ID} \
            --region=${REGION}
        
        log_info "Cluster created successfully"
    fi
    
    log_info "Getting cluster credentials..."
    gcloud container clusters get-credentials ${CLUSTER_NAME} \
        --region=${REGION} \
        --project=${PROJECT_ID}
    
    log_info "Connected to cluster"
}

deploy_bank_of_anthos() {
    log_step "Deploying Bank of Anthos..."
    
    log_info "Applying JWT secret..."
    kubectl apply -f ./extras/jwt/jwt-secret.yaml
    
    log_info "Deploying all services..."
    kubectl apply -f ./kubernetes-manifests
    
    log_info "Bank of Anthos deployment initiated"
}

wait_for_pods() {
    log_step "Waiting for pods to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local not_ready=$(kubectl get pods --no-headers 2>/dev/null | grep -v "Running\|Completed" | wc -l)
        
        if [ $not_ready -eq 0 ]; then
            local total_pods=$(kubectl get pods --no-headers 2>/dev/null | wc -l)
            if [ $total_pods -gt 0 ]; then
                log_info "All pods are ready!"
                return 0
            fi
        fi
        
        echo -n "."
        sleep 5
        ((attempt++))
    done
    
    echo ""
    log_warning "Some pods may still be starting. Check status with: kubectl get pods"
}

check_status() {
    log_step "Deployment Status"
    
    echo -e "\n${BLUE}Pods:${NC}"
    kubectl get pods
    
    echo -e "\n${BLUE}Services:${NC}"
    kubectl get services
    
    local frontend_ip=$(kubectl get service frontend -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    
    if [ -n "$frontend_ip" ]; then
        echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}✨ Bank of Anthos is ready!${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "🌐 Frontend URL: ${BLUE}http://${frontend_ip}${NC}"
        echo -e "📊 Default credentials: username: ${YELLOW}testuser${NC} / password: ${YELLOW}password${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    else
        log_warning "Frontend LoadBalancer IP pending. Try again in a few minutes."
    fi
    
    echo -e "\n${BLUE}Next steps for the hackathon:${NC}"
    echo "1. Access the application at the URL above"
    echo "2. Start building your AI agent components"
    echo "3. Integrate with Gemini API for intelligent features"
    echo "4. Remember: Don't modify core Bank of Anthos code!"
}

destroy_all() {
    log_step "Destroying all resources..."
    
    read -p "Are you sure you want to delete the cluster and all resources? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_warning "Destruction cancelled"
        return
    fi
    
    log_info "Deleting cluster..."
    gcloud container clusters delete ${CLUSTER_NAME} \
        --region=${REGION} \
        --project=${PROJECT_ID} \
        --quiet
    
    log_info "All resources destroyed"
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -p)
            PROJECT_ID="$2"
            shift 2
            ;;
        -r)
            REGION="$2"
            shift 2
            ;;
        -c)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -a)
            ACTION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            ;;
    esac
done

if [ -z "$ACTION" ]; then
    usage
    exit 1
fi

check_prerequisites

case $ACTION in
    setup)
        setup_gcloud
        create_cluster
        log_info "Setup complete! Run with '-a deploy' to deploy Bank of Anthos"
        ;;
    deploy)
        gcloud container clusters get-credentials ${CLUSTER_NAME} \
            --region=${REGION} \
            --project=${PROJECT_ID} 2>/dev/null || \
            log_error "Cluster not found. Run with '-a setup' first"
        
        deploy_bank_of_anthos
        wait_for_pods
        check_status
        ;;
    status)
        gcloud container clusters get-credentials ${CLUSTER_NAME} \
            --region=${REGION} \
            --project=${PROJECT_ID} 2>/dev/null || \
            log_error "Cluster not found. Run with '-a setup' first"
        
        check_status
        ;;
    destroy)
        destroy_all
        ;;
    all)
        setup_gcloud
        create_cluster
        deploy_bank_of_anthos
        wait_for_pods
        check_status
        ;;
    *)
        log_error "Unknown action: $ACTION"
        ;;
esac